// 职责: 冒烟测试 6 — 导出服务模型与授权页入口可达性。
// 关联文件:
//   lib/shared/services/novel_export.dart（NovelExportOptions / Labels / Payload / Bundle）
//   lib/desktop/pages/license_page.dart（LicensePage）
//   lib/desktop/widgets/license/license_pricing_view.dart（LicensePricingView）
//
// 说明:
//   - NovelExportService.buildBundle 需要 NovelContentService（内容库 DAO 依赖），
//     完整打包流程由既有 test/shared/services/novel_export_test.dart 覆盖；
//     本文件只做导出选项/标签/载荷的纯模型断言，不触碰真实 sqlite 与临时目录。
//   - LicensePage 通过 ProviderScope + EasyLocalization + RevericTheme 包裹后 pump，
//     断言 Scaffold / AppBar / LicensePricingView 三个入口组件均可挂载；
//     授权码激活的网络/校验路径由 license_gate_smoke_test.dart 与既有设置页测试覆盖。

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide LicensePage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/pages/license_page.dart';
import 'package:reveric/desktop/widgets/license/license_pricing_view.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/services/novel_export.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  group('导出选项与载荷模型', () {
    NovelExportLabels _labels() => NovelExportLabels(
      sections: {
        for (final scope in NovelExportScope.values) scope: 'section',
      },
      settingSections: {
        for (final section in NovelExportSettingSection.values)
          section: 'setting-section',
      },
      fields: {for (final field in NovelExportField.values) field: 'field'},
      storyOutline: 'story outline',
      chapterOutline: 'chapter outline',
      untitled: 'untitled',
      untitledBeat: 'untitled beat',
      fieldSeparator: ' / ',
    );

    test('默认导出选项只含正文范围；includes 按集合判定', () {
      final options = NovelExportOptions(
        chapterNumberFormat: NovelExportChapterNumberFormat.number,
        chapterTitleAlignment: NovelExportChapterTitleAlignment.left,
        labels: _labels(),
      );
      expect(options.scopes, {NovelExportScope.body});
      expect(options.includes(NovelExportScope.body), isTrue);
      expect(options.includes(NovelExportScope.outlines), isFalse);
    });

    test('标签映射可按 scope / settingSection / field 查表', () {
      final labels = _labels();
      expect(labels.section(NovelExportScope.materials), 'section');
      expect(
        labels.settingSection(NovelExportSettingSection.factions),
        'setting-section',
      );
      expect(labels.field(NovelExportField.author), 'field');
    });

    test('导出载荷保留文件名与正文内容', () {
      const payload = NovelExportPayload(
        fileName: 'novel.txt',
        content: '正文内容',
      );
      expect(payload.fileName, 'novel.txt');
      expect(payload.content, '正文内容');
    });

    test('显式声明的导出范围集合可包含多个 scope', () {
      final options = NovelExportOptions(
        chapterNumberFormat: NovelExportChapterNumberFormat.chinese,
        chapterTitleAlignment: NovelExportChapterTitleAlignment.center,
        labels: _labels(),
        scopes: {NovelExportScope.outlines, NovelExportScope.body},
      );
      expect(options.includes(NovelExportScope.outlines), isTrue);
      expect(options.includes(NovelExportScope.body), isTrue);
      expect(options.includes(NovelExportScope.materials), isFalse);
    });
  });

  group('授权页入口可达性', () {
    testWidgets('LicensePage 挂载出 Scaffold / AppBar / LicensePricingView', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: EasyLocalization(
            supportedLocales: const [Locale('en')],
            startLocale: const Locale('en'),
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
                  child: const LicensePage(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(); // LicensePricingView.initState 异步读取授权状态
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(Scaffold), findsWidgets);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(LicensePricingView), findsOneWidget);
      expect(find.byType(LicensePage), findsOneWidget);
    });
  });
}
