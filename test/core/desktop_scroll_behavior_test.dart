import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/desktop_scroll_behavior.dart';

/// 桌面拖曳捲動(2026-08-11 實機)。
///
/// Flutter 桌面的預設 `dragDevices` **不含 mouse**,橫向清單在 macOS 上既
/// 不能拖也不吃垂直滾輪,內容超出寬度就再也看不到。實機現象:族群排行切到
/// 「轉向」後 11+ 張卡片,超出的那幾張滑不到。
///
/// 全專案有 8 處 `scrollDirection: Axis.horizontal`,先前只有
/// `upcoming_events_section` 自己包了 ScrollConfiguration——修一處等於留
/// 七個同樣的坑,所以改設在 MaterialApp 全域。
void main() {
  test('🚨 mouse 與 trackpad 必須在 dragDevices 內', () {
    const behavior = DesktopDragScrollBehavior();
    expect(
      behavior.dragDevices,
      containsAll(<PointerDeviceKind>[
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      ]),
      reason: 'macOS 主要靠這兩個;少任何一個橫向卡列就拖不動',
    );
  });

  test('原本就支援的 touch/stylus 不可被弄丟', () {
    const behavior = DesktopDragScrollBehavior();
    expect(
      behavior.dragDevices,
      containsAll(<PointerDeviceKind>[
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      ]),
      reason: '加桌面支援時不該把行動裝置的拿掉',
    );
  });
}
