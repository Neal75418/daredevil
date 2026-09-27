#!/usr/bin/env python3
"""產業領導（sector rotation）factor 全期驗證 — calibration.db。

選股 factor 改動的「全期 gate」研究工具（呼應 score_validate.dart 的紀律：用
calibration.db 多 regime 全期、不只看近期窗）。本檔驗「族群 20D 動能（成員股中位數）
百分位 能否預測 forward 20D 超額報酬」。

**2026-06-28 結論：無持續 edge**（全期 IC −0.012、上升 regime −0.008、逐年 2021~2025
皆 ≈0/負，只有 2026 +0.127 單年 outlier）。先前只用 live DB 近期窗（2025-2026）得到的
+0.054 是假陽性 → 產業 tilt 維持 dormant（SectorParams.tiltWeight=0）。

教訓：factor 一律在這份全期資料驗，近期窗會把單年 regime 運氣誤判成 edge。
此檔也是日後 RS / 其他 factor 驗證的模板（換掉因子定義即可）。

用法：
    python3 tool/sector_factor_validate.py                 # 預設讀 tool/calibration.db
    python3 tool/sector_factor_validate.py --db /path/to.sqlite
calibration.db 由 tool/backfill.dart 產生（gitignored、非交付物）。
"""
import argparse
import os
import sqlite3
import statistics as st

LOOKBACK = 20          # factor 動能窗
FORWARD = 20           # forward 報酬窗
STEP = 5               # as-of 取樣間隔
REGIME_LB = 120        # regime gate 市場趨勢窗（長窗排除空頭反彈）
MIN_TURNOVER = 30_000_000
MIN_MEMBERS = 3        # 產業最少成員數


def spearman(xs, ys):
    n = len(xs)
    if n < 5:
        return None

    def rank(v):
        order = sorted(range(n), key=lambda i: v[i])
        r = [0.0] * n
        i = 0
        while i < n:
            j = i
            while j + 1 < n and v[order[j + 1]] == v[order[i]]:
                j += 1
            for k in range(i, j + 1):
                r[order[k]] = (i + j) / 2.0
            i = j + 1
        return r

    rx, ry = rank(xs), rank(ys)
    mx, my = sum(rx) / n, sum(ry) / n
    num = sum((rx[i] - mx) * (ry[i] - my) for i in range(n))
    dx = sum((rx[i] - mx) ** 2 for i in range(n)) ** 0.5
    dy = sum((ry[i] - my) ** 2 for i in range(n)) ** 0.5
    return num / (dx * dy) if dx and dy else None


def summarize(label, vals):
    if not vals:
        print(f"{label}: (無樣本)")
        return
    mean = sum(vals) / len(vals)
    pos = sum(1 for v in vals if v > 0) / len(vals) * 100
    sd = st.pstdev(vals) if len(vals) > 1 else 0
    t = mean / (sd / len(vals) ** 0.5) if sd > 0 else float("nan")
    print(f"{label}: n={len(vals):4d}  mean={mean:+.4f}  正比例={pos:3.0f}%  t≈{t:+.2f}")


def load_prices(db_path):
    """讀 stock_master 與 daily_price → (symbol→industry, 交易日序列, symbol→{date: (close, vol)})。"""
    con = sqlite3.connect(db_path)
    industry = dict(con.execute("SELECT symbol, industry FROM stock_master"))
    dates = [r[0][:10] for r in con.execute(
        "SELECT DISTINCT date FROM daily_price ORDER BY date")]
    px = {}
    for sym, d, close, vol in con.execute(
            "SELECT symbol, date, close, volume FROM daily_price"):
        if close is not None:
            px.setdefault(sym, {})[d[:10]] = (close, vol or 0)
    con.close()
    return industry, dates, px


def collect_rows(industry, px, d_back, d_now, d_fwd, d_reg):
    """單一 as-of 日：每檔 (產業, 20D 動能, forward 20D 報酬) 與 regime 用的 120D 報酬。"""
    rows, reg = [], []
    for sym, dd in px.items():
        ind = industry.get(sym)
        if not ind or ind == "ETF":
            continue
        a, b, c = dd.get(d_back), dd.get(d_now), dd.get(d_fwd)
        if not a or not b or not c or a[0] <= 0 or b[0] <= 0:
            continue
        if b[0] * b[1] < MIN_TURNOVER:
            continue
        rows.append((ind, b[0] / a[0] - 1, c[0] / b[0] - 1))
        r = dd.get(d_reg)
        if r and r[0] > 0:
            reg.append(b[0] / r[0] - 1)
    return rows, reg


def evaluate_asof(rows, reg):
    """單一 as-of 日的 (IC, regime_up, 分位 spread)；樣本不足回 None。"""
    if len(rows) < 50 or len(reg) < 50:
        return None
    regime_up = sum(reg) / len(reg) > 0
    by_ind = {}
    for ind, r20, _ in rows:
        by_ind.setdefault(ind, []).append(r20)
    smom = {i: st.median(v) for i, v in by_ind.items() if len(v) >= MIN_MEMBERS}
    if len(smom) < 5:
        return None
    srt = sorted(smom, key=smom.get)
    m = len(srt)
    spct = {ind: i / (m - 1) for i, ind in enumerate(srt)}
    rr = [r for r in rows if r[0] in spct]
    mean_fw = sum(r[2] for r in rr) / len(rr)
    xs = [spct[r[0]] for r in rr]
    ys = [r[2] - mean_fw for r in rr]
    ic = spearman(xs, ys)
    if ic is None:
        return None
    paired = sorted(zip(xs, ys))
    k = max(1, len(paired) // 5)
    qs = sum(y for _, y in paired[-k:]) / k - sum(y for _, y in paired[:k]) / k
    return ic, regime_up, qs


def report(recs):
    up = [ic for _, ic, u, _ in recs if u]
    dn = [ic for _, ic, u, _ in recs if not u]
    print("=" * 62)
    print(f"產業領導 factor 全期驗證（{len(recs)} as-of、regime gate {REGIME_LB}D）")
    print("=" * 62)
    print("\n【IC：族群動能百分位 vs forward 20D 超額】")
    summarize("  全期", [ic for _, ic, _, _ in recs])
    summarize("  上升 regime（套 tilt）", up)
    summarize("  下降 regime（gate→關）", dn)
    print("\n【分位 spread：最強族 20% − 最弱族 20%】")
    summarize("  上升 regime", [q for _, _, u, q in recs if u])
    summarize("  下降 regime", [q for _, _, u, q in recs if not u])
    print("\n【逐年 IC】")
    by_yr = {}
    for d, ic, u, _ in recs:
        by_yr.setdefault(d[:4], []).append((ic, u))
    for yr in sorted(by_yr):
        v = by_yr[yr]
        ics = [x[0] for x in v]
        nu = sum(1 for _, u in v if u)
        print(f"  {yr}: IC {sum(ics) / len(ics):+.3f}  (n={len(ics):3d}, 上升{nu}/下降{len(v) - nu})")
    if up:
        mu = sum(up) / len(up)
        print(f"\n判讀：上升 regime IC {mu:+.3f} → "
              + ("有 edge、可考慮啟用" if mu > 0.02
                 else "無持續 edge → tilt 維持 dormant（W=0）"))


def main():
    ap = argparse.ArgumentParser()
    default_db = os.path.join(os.path.dirname(os.path.abspath(__file__)), "calibration.db")
    ap.add_argument("--db", default=default_db, help="價格 SQLite（預設 tool/calibration.db）")
    args = ap.parse_args()

    industry, dates, px = load_prices(args.db)
    print(f"資料 {dates[0]} ~ {dates[-1]}、{len(dates)} 交易日、{len(px)} 檔\n")

    recs = []  # (date, ic, regime_up, qspread)
    for gi in range(max(LOOKBACK, REGIME_LB), len(dates) - FORWARD, STEP):
        d_back, d_now, d_fwd = dates[gi - LOOKBACK], dates[gi], dates[gi + FORWARD]
        d_reg = dates[gi - REGIME_LB]
        rows, reg = collect_rows(industry, px, d_back, d_now, d_fwd, d_reg)
        r = evaluate_asof(rows, reg)
        if r is not None:
            recs.append((d_now, *r))
    report(recs)


if __name__ == "__main__":
    main()
