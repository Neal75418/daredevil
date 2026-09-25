import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/app/router.dart';
import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/presentation/screens/onboarding/disclaimer_screen.dart';

/// 進入 App 的閘門順序：引導 → 免責聲明同意 → 主畫面。
///
/// 🚨 免責同意必須是獨立旗標：既有安裝早已完成引導，若只把聲明塞進引導頁，
/// 它們永遠看不到、也永遠沒有按過同意。
void main() {
  String? redirect({
    required bool onboarded,
    required bool accepted,
    String at = AppRoutes.home,
  }) => resolveEntryRedirect(
    onboardingComplete: onboarded,
    disclaimerAccepted: accepted,
    location: at,
  );

  test('沒做過引導 → 先去引導', () {
    expect(redirect(onboarded: false, accepted: false), AppRoutes.onboarding);
  });

  test('🚨 既有安裝（已引導、未同意）→ 免責聲明頁', () {
    expect(redirect(onboarded: true, accepted: false), AppRoutes.disclaimer);
    expect(
      redirect(
        onboarded: true,
        accepted: false,
        at: AppRoutes.stockDetail('2330'),
      ),
      AppRoutes.disclaimer,
      reason: '深層連結也不能繞過',
    );
  });

  test('已同意 → 不攔截', () {
    expect(redirect(onboarded: true, accepted: true), isNull);
    expect(
      redirect(onboarded: true, accepted: true, at: AppRoutes.scan),
      isNull,
    );
  });

  test('已在目標頁時不重導（避免無限迴圈）', () {
    expect(
      redirect(onboarded: false, accepted: false, at: AppRoutes.onboarding),
      isNull,
    );
    expect(
      redirect(onboarded: true, accepted: false, at: AppRoutes.disclaimer),
      isNull,
    );
  });

  test('完成後停在引導或聲明頁 → 回主畫面', () {
    expect(
      redirect(onboarded: true, accepted: true, at: AppRoutes.onboarding),
      AppRoutes.home,
    );
    expect(
      redirect(onboarded: true, accepted: true, at: AppRoutes.disclaimer),
      AppRoutes.home,
    );
    expect(
      redirect(onboarded: true, accepted: false, at: AppRoutes.onboarding),
      AppRoutes.disclaimer,
    );
  });

  // redirect 讀的是 router 的快取旗標；純函式測不到「有沒有從偏好設定
  // 讀進來、同意後有沒有寫回去」。
  group('同意狀態的讀寫', () {
    test('🚨 冷啟動要讀回已同意，否則每次開 App 都得重新同意', () async {
      SharedPreferences.setMockInitialValues({
        DisclaimerScreen.acceptedKey: true,
      });
      await initOnboardingStatus();
      expect(isDisclaimerAccepted, isTrue);
    });

    test('未同意的安裝讀回 false', () async {
      SharedPreferences.setMockInitialValues({});
      await initOnboardingStatus();
      expect(isDisclaimerAccepted, isFalse);
    });

    test('同意後快取立即更新並持久化', () async {
      SharedPreferences.setMockInitialValues({});
      await initOnboardingStatus();

      await acceptDisclaimer();

      expect(isDisclaimerAccepted, isTrue, reason: 'redirect 讀快取');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(DisclaimerScreen.acceptedKey), isTrue);
    });
  });
}
