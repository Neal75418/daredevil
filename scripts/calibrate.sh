#!/usr/bin/env bash
#
# scripts/calibrate.sh — Stage 3+4 one-shot calibration pipeline
#
# 一次跑完 backfill → replay → recalibrate 三階段，產出 candidate JSON 供人工 review。
#
# ## 為什麼不用 dart run
#
# tool/backfill.dart 跟 tool/replay_calibrator.dart 透過 AppDatabase 間接 import
# 了 drift_flutter → dart:ui → Flutter framework 整個 compilation chain。純 Dart
# VM（`dart run`）沒有 dart:ui，compile time 就爆。
#
# 解法：用 `flutter test` 載入 Flutter runtime（有 dart:ui），test wrapper
# 在 `test/tool/run_backfill.dart` + `test/tool/run_replay.dart` 呼叫每個 tool
# 的 runXxxCli(args) 函式。`tool/recalibrate.dart` 原本就是純 sqlite3 不用 Flutter，
# 直接 `dart run` 就行。
#
# ## 使用方式
#
#     export FINMIND_TOKEN=eyJ...          # FinMind API token，必填
#     ./scripts/calibrate.sh                # 用預設值跑完整 pipeline
#
#     # 可選環境變數 —— 全部由 test/tool/run_backfill.dart 與 run_replay.dart
#     # 直接讀取，此處未列出的等同不存在（守門：scripts_env_documented_test）
#
#     # 範圍
#     export CALIBRATION_DB=tool/calibration.db  # DB 路徑，預設 tool/calibration.db
#     export BACKFILL_YEARS=2               # 回溯年數，預設 2
#     export BACKFILL_START_DATE=2020-07-01 # 明確起日（優先於 YEARS）
#     export BACKFILL_END_DATE=2026-08-01   # 明確迄日
#     export BACKFILL_SYMBOLS=2330,2317     # 限定 symbol（測試用，加速）
#
#     # 跳過／限定 phase
#     export BACKFILL_SKIP_FUNDAMENTALS=1   # 跳過 revenue/financial/valuation
#     export BACKFILL_SKIP_DAY_TRADING=1    # 跳過當沖
#     export BACKFILL_ONLY_DAY_TRADING=1    # 只補當沖（既有 DB 已有價格時）
#     export BACKFILL_DAY_TRADING_MAX_DAYS=60  # 當沖單輪上限
#     export BACKFILL_PRICES_VIA_FINMIND=1  # 價格改走 FinMind（TWSE 不可用時）
#     export BACKFILL_DRY_RUN=1             # dry run，不實際抓取
#
#     # Replay 階段
#     export REPLAY_MIN_HISTORY=60          # 最少歷史天數
#     export REPLAY_SYMBOLS=2330,2317       # 限定 symbol
#     export REPLAY_DRY_RUN=1               # 只印計畫不執行
#
# ## 🚨 BACKFILL_SKIP_FUNDAMENTALS 的實務意義（2026-08-22 實測）
#
# 基本面三個 phase 需約 7,100 次 FinMind 呼叫，額度 600/hr → 單次跑不完
# （約 12 小時），而撞限流會 **abort 整個 backfill**，連帶讓下一輪只打 1 次
# 的 stock_list 也被鎖在門外。若這次目的是重跑校準而非補基本面，設為 1。
#
#     ./scripts/calibrate.sh
#
# ## Pipeline 失敗怎麼辦
#
# - Backfill 失敗（rate limit / network）：`./scripts/calibrate.sh` 會 abort。
#   等一陣子後重跑，已完成的部分會被 skip-existing 機制自動跳過（resumable）。
# - Replay 失敗（沒有 rule firing）：backfill 資料可能不完整，檢查
#   tool/calibration.db 的 daily_price 表筆數是否合理。
# - Recalibrate 失敗：通常是 rule_accuracy 表內容有問題。檢查 replay.log。
#
# ## Pipeline 成功後
#
# 產出：
#   assets/rule_scores_calibrated_short_candidate.json
#   assets/rule_scores_calibrated_long_candidate.json
#
# Review 這兩個檔案，通過後手動 rename：
#   mv assets/rule_scores_calibrated_short_candidate.json \
#      assets/rule_scores_calibrated_short.json
#   mv assets/rule_scores_calibrated_long_candidate.json \
#      assets/rule_scores_calibrated_long.json
#
# 然後 `flutter run` 驗證 Today 畫面短/長線切換有實際差異，git commit + push。

set -euo pipefail

# ============================================================================
# Prerequisites
# ============================================================================

if [ -z "${FINMIND_TOKEN:-}" ]; then
  echo "❌ FINMIND_TOKEN 環境變數未設定"
  echo ""
  echo "請先設定："
  echo "  export FINMIND_TOKEN=<你的 token>"
  echo ""
  echo "或寫進 ~/.zshrc / ~/.bashrc 讓每次開 shell 自動載入。"
  exit 1
fi

# 自動切到 repo root（script 可能從任何目錄呼叫）
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -f "pubspec.yaml" ]; then
  echo "❌ 找不到 pubspec.yaml — scripts/calibrate.sh 必須從 Daredevil repo root 執行"
  exit 1
fi

# ============================================================================
# Concurrency guard — 防止同時兩個 calibrate 污染 tool/calibration.db
#
# replay_calibrator.dart 會 `delete(ruleAccuracy).go()` 再全量重寫，兩個 process
# 並跑會產生刪除/插入交疊的資料，下游 recalibrate 吃到混合結果。
#
# 用 mkdir 做 atomic lock（macOS 沒 flock）。PID 寫進 lock dir 方便診斷殘檔。
# ============================================================================

LOCKDIR="$REPO_ROOT/tool/.calibrate.lock"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  STALE_PID="unknown"
  if [ -f "$LOCKDIR/pid" ]; then
    STALE_PID="$(cat "$LOCKDIR/pid")"
  fi
  echo "❌ calibrate 已在執行中（lockdir: $LOCKDIR, pid: $STALE_PID）" >&2
  echo "   若該 process 已死（\`ps -p $STALE_PID\` 查不到），手動清掉：" >&2
  echo "     rm -rf \"$LOCKDIR\"" >&2
  exit 1
fi
echo "$$" > "$LOCKDIR/pid"
trap 'rm -rf "$LOCKDIR"' EXIT INT TERM

# ============================================================================
# Config defaults
# ============================================================================

: "${BACKFILL_YEARS:=2}"
: "${CALIBRATION_DB:=tool/calibration.db}"
: "${BACKFILL_SYMBOLS:=}"
: "${BACKFILL_DRY_RUN:=0}"

export BACKFILL_YEARS
export CALIBRATION_DB
export BACKFILL_SYMBOLS
export BACKFILL_DRY_RUN

echo "=========================================================="
echo "🚀 Stage 3+4 Calibration Pipeline"
echo "=========================================================="
echo "  Repo:        $REPO_ROOT"
echo "  DB:          $CALIBRATION_DB"
echo "  Years:       $BACKFILL_YEARS"
if [ -n "$BACKFILL_SYMBOLS" ]; then
  echo "  Symbols:     $BACKFILL_SYMBOLS"
else
  echo "  Symbols:     (all active)"
fi
if [ "$BACKFILL_DRY_RUN" = "1" ]; then
  echo "  Mode:        DRY RUN"
fi
echo "=========================================================="
echo ""

# 過大年數警告
if [ "$BACKFILL_YEARS" -gt 5 ]; then
  echo "⚠️  BACKFILL_YEARS=$BACKFILL_YEARS 很大，FinMind 可能回傳不完整歷史且耗時數天"
  echo ""
fi

# ============================================================================
# Stage 1 — Backfill
# ============================================================================

echo "▶️  Stage 1 — Historical backfill"
echo "   （可能跑 ~9 小時，建議 overnight 配 tmux/nohup）"
echo ""

flutter test test/tool/run_backfill.dart --reporter=expanded

echo ""
echo "✅ Backfill 完成"
echo ""

# Dry run 只跑 stage 1 就結束
if [ "$BACKFILL_DRY_RUN" = "1" ]; then
  echo "（dry run 模式，跳過 replay + recalibrate）"
  exit 0
fi

# ============================================================================
# Stage 2 — Replay calibrator
# ============================================================================

echo "▶️  Stage 2 — Replay calibrator (~30-60 分鐘)"
echo ""

flutter test test/tool/run_replay.dart --reporter=expanded

echo ""
echo "✅ Replay 完成"
echo ""

# ============================================================================
# Stage 3 — Recalibrate (pure Dart, no Flutter runtime needed)
# ============================================================================

echo "▶️  Stage 3 — Recalibrate (產出 candidate JSON)"
echo ""

dart run tool/recalibrate.dart --db "$CALIBRATION_DB"

echo ""
echo "✅ Recalibrate 完成"
echo ""

# ============================================================================
# Summary + next steps
# ============================================================================

echo "=========================================================="
echo "✅ PIPELINE COMPLETE"
echo "=========================================================="
echo ""
echo "產出的 candidate JSON："
ls -la assets/rule_scores_calibrated_*_candidate.json 2>/dev/null || echo "  (沒找到 candidate 檔案，請檢查 recalibrate log)"
echo ""
echo "下一步（人工 review）："
echo ""
echo "  1. 檢查 candidate JSON："
echo "     cat assets/rule_scores_calibrated_short_candidate.json | jq ."
echo "     cat assets/rule_scores_calibrated_long_candidate.json | jq ."
echo ""
echo "  2. Review checklist（設計文件 §5.5）："
echo "     - 多少 rule active vs cut？預期 30-50 / 62"
echo "     - 4 個 current-day-only rule 是否 cut 成 'insufficient_samples'？"
echo "     - Active rule 分數在 [10, 35] 範圍？"
echo "     - 短/長線排序有意義差異？（完全一樣代表出問題）"
echo ""
echo "  3. 通過後 rename candidate → production："
echo ""
echo "     mv assets/rule_scores_calibrated_short_candidate.json \\"
echo "        assets/rule_scores_calibrated_short.json"
echo "     mv assets/rule_scores_calibrated_long_candidate.json \\"
echo "        assets/rule_scores_calibrated_long.json"
echo ""
echo "  4. Smoke test："
echo "     flutter run"
echo "     （切換 Today 畫面短/長線，確認 Top 20 真的不同）"
echo ""
echo "  5. Commit + push 完成 Stage 4"
echo ""
