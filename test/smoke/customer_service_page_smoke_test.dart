// 职责: 冒烟测试 — 客服反馈内嵌页在首页内嵌形态下可挂载，页头容器与内容视图齐全。
// 关联文件:
//   lib/desktop/pages/customer_service_page.dart
//   lib/shared/widgets/support/customer_service_feedback_view.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/pages/customer_service_page.dart';
import 'package:reveric/desktop/widgets/agent_management/home_management_cards.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/support/customer_service_feedback_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpPage(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final headerKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        child: EasyLocalization(
          supportedLocales: const <Locale>[Locale('zh', 'CN')],
          startLocale: const Locale('zh', 'CN'),
          fallbackLocale: const Locale('en'),
          saveLocale: false,
          path: 'assets/translations',
          assetLoader: const MergingAssetLoader(),
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: RevericThemeData.reveric.toThemeData(),
              home: RevericTheme(
                data: RevericThemeData.reveric,
                // 真实首页中该页位于 HomePage 的 Scaffold 内，测试同样补一层，
                // 提供 Material / ScaffoldMessenger 祖先。
                child: Scaffold(
                  body: DesktopCustomerServicePage(
                    headerGestureExclusionKey: headerKey,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('客服反馈内嵌页', () {
    for (final size in const <Size>[Size(1440, 900), Size(900, 800)]) {
      testWidgets('${size.width}x${size.height} 挂载页头容器与内容视图', (
        tester,
      ) async {
        await pumpPage(tester, size);

        expect(find.byType(HomeManagementScaffold), findsOneWidget);
        expect(find.byType(CustomerServiceFeedbackView), findsOneWidget);
        expect(find.byType(Image), findsWidgets);
        expect(find.text('客服反馈'), findsWidgets);
      });
    }
  });
}
