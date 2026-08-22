#!/usr/bin/env bash
#
# scripts/calibrate-retry.sh — calibrate.sh 的 rate-limit retry wrapper
#
# 自動偵測 TWSE rate limit 並 sleep 15 分鐘重跑，最多 MAX_RETRIES 輪。
# 每輪 calibrate.sh 跑 ~7-15 分鐘可以推進 60-120 trading days，
# 一次完整 2 年 backfill 預計 3-6 輪、總時間 3-5 小時。
#
# ## 使用
#
#     export FINMIND_TOKEN=eyJ...
#     ./scripts/calibrate-retry.sh                # 預設 30 retry × 15min
#
#     # 可選 env vars（會傳給 calibrate.sh）
#     export BACKFILL_YEARS=2                     # 預設 2
#     export BACKFILL_SYMBOLS=2330,2317           # 預設全市場
#     export BACKFILL_INTER_DAY_DELAY_MS=5000     # 預設 5000ms
#     ./scripts/calibrate-retry.sh
#
#     # 調 retry / sleep
#     MAX_RETRIES=10 SLEEP_BETWEEN_RETRIES=600 ./scripts/calibrate-retry.sh
#
# ## 背景跑 + 監看
#
#     nohup ./scripts/calibrate-retry.sh >> calibrate.log 2>&1 &
#     tail -f calibrate.log
#
#     # 確認 process 還活著
#     ps aux | grep -E "calibrate" | grep -v grep
#
#     # 看 retry 歷史
#     grep "attempt" calibrate.log
#
#     # 中止
#     pkill -f "scripts/calibrate"
#
# ## 為什麼不直接 `while ! ./scripts/calibrate.sh; do`
#
# 踩過的兩個 bash 陷阱：
#
# 1. **`!` 反轉 exit code**：`while ! cmd; do code=$?` 抓到的是 `!` 反轉
#    後的值（0），不是 cmd 真實 exit code（4）。改用 `cmd && exit 0` +
#    後續處理。
#
# 2. **Test runner 包覆 exit code**：calibrate.sh 內部跑 `flutter test`，
#    test runner 把 backfill 工具的 exit 4（rate limit）統一包成 exit 1
#    （test failed）。即使 calibrate.sh 內 docstring 寫「exit 4 = rate
#    limit」，wrapper 之外看到的是 1，無法靠 exit code 區分 rate limit
#    vs 其他失敗。改用 log content grep "API rate limit exceeded" 判斷。
#
# 同時記錄 calibrate 跑之前的 log 行數，retry 判斷只看新增的行，避免
# 上一輪殘留的 "rate limit" 字串誤觸發。

set -uo pipefail
# 不用 `set -e` — 我們需要自己判斷 calibrate.sh 失敗原因

# ============================================================================
# Config
# ============================================================================

: "${MAX_RETRIES:=30}"
: "${SLEEP_BETWEEN_RETRIES:=900}"  # 15 分鐘
: "${CALIBRATE_LOG:=$(cd "$(dirname "$0")/.." && pwd)/calibrate.log}"

# 自動切到 repo root（script 可能從任何目錄呼叫）
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || { echo "❌ 無法切換到 repo root: $REPO_ROOT" >&2; exit 1; }

# ============================================================================
# Prerequisites
# ============================================================================

if [ -z "${FINMIND_TOKEN:-}" ]; then
  echo "❌ FINMIND_TOKEN 環境變數未設定" >&2
  echo "" >&2
  echo "請先設定：" >&2
  echo "  export FINMIND_TOKEN=<你的 token>" >&2
  exit 1
fi

if [ ! -x "scripts/calibrate.sh" ]; then
  echo "❌ scripts/calibrate.sh 不存在或不可執行" >&2
  exit 1
fi

# ============================================================================
# Retry loop
# ============================================================================

echo "=========================================================="
echo "🔁 Calibrate Retry Wrapper"
echo "=========================================================="
echo "  Max retries:           $MAX_RETRIES"
echo "  Sleep between retries: ${SLEEP_BETWEEN_RETRIES}s"
echo "  Log:                   $CALIBRATE_LOG"
echo "  Start:                 $(date)"
echo "=========================================================="
echo ""

for i in $(seq 1 "$MAX_RETRIES"); do
  echo "[$(date)] attempt $i/$MAX_RETRIES: starting calibrate.sh"

  # 這輪的輸出自己接住，不依賴呼叫端有沒有把 stdout 重導向到 CALIBRATE_LOG。
  #
  # 🚨 2026-08-22 實測:舊版記錄 CALIBRATE_LOG 的行數、跑完再 tail 新增行來
  # 判斷是不是限流。但 calibrate.sh 自己不寫那個檔——重導向是呼叫端的責任。
  # 少打一個 `>> calibrate.log 2>&1`，new_lines 就永遠是空字串，任何失敗都會
  # 被判成 non-transient 直接 abort，**retry 等於關掉且毫無警告**。
  # 改成用 tee 直接接住 calibrate.sh 的輸出:照樣即時顯示、照樣累積到 log，
  # 但判斷限流用的是自己手上這一輪的內容，與呼叫端怎麼跑無關。
  round_log="$(mktemp -t calibrate-round)"

  # `PIPESTATUS[0]` 取的是 calibrate.sh 的 exit code，不是 tee 的。
  # 刻意不動 `pipefail`：腳本開頭已 `set -uo pipefail`，而 PIPESTATUS
  # 本來就與 pipefail 無關；在這裡 `set +o pipefail` 會從第二輪起關掉
  # 開頭刻意開啟的選項。
  ./scripts/calibrate.sh 2>&1 | tee -a "$CALIBRATE_LOG" "$round_log"
  exit_code=${PIPESTATUS[0]}

  if [ "$exit_code" -eq 0 ]; then
    rm -f "$round_log"
    echo ""
    echo "[$(date)] attempt $i: ✅ PIPELINE COMPLETE"
    exit 0
  fi

  new_lines=$(cat "$round_log")
  rm -f "$round_log"

  # Transient failures：rate limit + network error 都 retry
  # - rate limit: TWSE 短期 IP cooldown (~15min)
  # - network error: TPEx server 偶爾主動斷線（HttpException: Connection closed）
  #                  → 短 sleep 60s 即可（不是 rate limit）
  if echo "$new_lines" | grep -q "API rate limit exceeded"; then
    echo "[$(date)] attempt $i: rate limit，sleep ${SLEEP_BETWEEN_RETRIES}s"
    sleep "$SLEEP_BETWEEN_RETRIES"
  elif echo "$new_lines" | grep -q "Network error"; then
    echo "[$(date)] attempt $i: network error，sleep 60s"
    sleep 60
  else
    echo "[$(date)] attempt $i: non-transient failure (exit $exit_code)，aborting" >&2
    echo "Last 50 lines of this round:" >&2
    echo "$new_lines" | tail -50 >&2
    exit "$exit_code"
  fi
done

echo "[$(date)] ❌ Exceeded $MAX_RETRIES retries，giving up" >&2
exit 1
