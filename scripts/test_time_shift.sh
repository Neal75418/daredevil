#!/usr/bin/env bash
# 撥時間跑測試：把 lib／tool 的「現在」往後撥 N 天，找出過了某天才會紅的
# 測試（時間炸彈）。key 由這支腳本帶，不手打——拼錯時讀到空值、等於沒撥。
#
# 用法：scripts/test_time_shift.sh <天數> [flutter test 的其他參數或測試路徑…]
set -euo pipefail

days="${1:?用法：scripts/test_time_shift.sh <天數> [測試路徑…]}"
shift
[[ "$days" =~ ^-?[0-9]+$ ]] || { echo "天數要是整數：$days" >&2; exit 2; }

# EXPECT_TIME_SHIFT_DAYS 讓 device_time_test 核對平移真的生效（--dart-define 的
# 名稱被改壞時，平移會靜默變 0、全套照樣綠）
EXPECT_TIME_SHIFT_DAYS="$days" exec flutter test --dart-define=TEST_TIME_SHIFT_DAYS="$days" "$@"
