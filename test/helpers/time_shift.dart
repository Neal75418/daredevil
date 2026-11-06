/// `--dart-define=TEST_TIME_SHIFT_DAYS` 的值 → 平移（沒給為 0）。
///
/// 格式錯直接丟 [FormatException]，不當成 0：靜默不平移時全套照樣綠，會被
/// 誤記成「撥了 N 天也沒有時間炸彈」。key 拼錯讀到的是空字串、這裡分辨
/// 不出來，所以撥時間跑全套一律用 `scripts/test_time_shift.sh`，不手打。
Duration timeShiftFromDefine(String raw) =>
    Duration(days: raw.isEmpty ? 0 : int.parse(raw));
