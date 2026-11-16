// 职责: 冒烟测试 — 授权页在宽中窄三档宽度下都能完整布局，
//   且三档方案卡片的购买按钮落在同一条水平线上。
// 关联文件:
//   lib/desktop/pages/license_page.dart
//   lib/desktop/widgets/license/license_pricing_view.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide LicensePage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:reveric/desktop/pages/license_page.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpLicensePage(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
              localizationsDelegates: <LocalizationsDelegate<dynamic>>[
                ...context.localizationDelegates,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: RevericThemeData.reveric.toThemeData(),
              home: RevericTheme(
                data: RevericThemeData.reveric,
                child: const LicensePage(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('授权页布局', () {
    for (final size in const <Size>[
      Size(1440, 900),
      Size(1000, 800),
      Size(520, 900),
    ]) {
      testWidgets('${size.width}x${size.height} 无溢出且渲染出方案卡片与二维码', (
        tester,
      ) async {
        await pumpLicensePage(tester, size);
        expect(tester.takeException(), isNull);
        expect(find.text('选择你的版本'), findsOneWidget);
        expect(find.text('购买与咨询'), findsOneWidget);
        expect(find.byType(Image), findsWidgets);
      });
    }

    testWidgets('宽屏下三档购买按钮顶部对齐', (tester) async {
      await pumpLicensePage(tester, const Size(1440, 900));
      final buttons = find.byWidgetPredicate(
        (widget) => widget is FilledButton || widget is OutlinedButton,
      );
      final rects = <Rect>[
        for (var i = 0; i < buttons.evaluate().length; i++)
          tester.getRect(buttons.at(i)),
      ];
      final groups = <int, List<Rect>>{};
      for (final rect in rects) {
        final key = rect.top.round();
        groups.putIfAbsent(key, () => <Rect>[]).add(rect);
      }
      final alignedGroup = groups.values
          .where((group) => group.length >= 3)
          .toList();
      expect(alignedGroup, isNotEmpty);
    });
  });
}
