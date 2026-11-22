// 职责: 验证章节编辑页「本章出场」条的三种状态（正常/空/无人物卡）
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_cast_strip.dart
//   lib/shared/services/chapter_cast.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/desktop/widgets/workspace/chapter_cast_strip.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/character_profile.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

CharacterProfile _character({required String id, required String name}) {
  final now = DateTime(2026, 11, 22);
  return CharacterProfile(
    id: id,
    name: name,
    role: characterRoleSupporting,
    gender: characterGenderUnknown,
    aliases: const [],
    tags: const [],
    identity: '',
    age: '未知',
    motivation: '',
    arc: '',
    appearance: '',
    description: '',
    biography: '',
    personality: '',
    behaviorTags: const [],
    currentState: '',
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
    photos: const [],
  );
}

Future<void> _pumpStrip(
  WidgetTester tester, {
  required TextEditingController outline,
  required TextEditingController content,
  required List<CharacterProfile> characters,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('zh', 'CN')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      fallbackLocale: const Locale('zh', 'CN'),
      startLocale: const Locale('zh', 'CN'),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            home: RevericTheme(
              data: RevericThemeData.reveric,
              child: Scaffold(
                body: ChapterCastStrip(
                  outlineController: outline,
                  contentController: content,
                  characters: characters,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('章纲里出现人名时列出该角色并标注只命中章纲', (tester) async {
    final outline = TextEditingController(text: '沈砚推门，柳七在灯下抄书');
    final content = TextEditingController(text: '');
    await _pumpStrip(
      tester,
      outline: outline,
      content: content,
      characters: [
        _character(id: 'c1', name: '沈砚'),
        _character(id: 'c2', name: '柳七'),
      ],
    );

    expect(find.text('沈砚'), findsOneWidget);
    expect(find.text('柳七'), findsOneWidget);
    expect(find.textContaining('正文 0'), findsOneWidget);
    expect(find.textContaining('章纲 2'), findsOneWidget);
    expect(find.text('正文未写，按章纲统计'), findsOneWidget);
  });

  testWidgets('正文写入后同一角色转为正文命中', (tester) async {
    final outline = TextEditingController(text: '沈砚推门');
    final content = TextEditingController(text: '沈砚坐下，沈砚开口。');
    await _pumpStrip(
      tester,
      outline: outline,
      content: content,
      characters: [_character(id: 'c1', name: '沈砚')],
    );

    expect(find.textContaining('正文 1'), findsOneWidget);
    expect(find.text('正文未写，按章纲统计'), findsNothing);
  });

  testWidgets('没有人物卡时说明无法反查', (tester) async {
    await _pumpStrip(
      tester,
      outline: TextEditingController(),
      content: TextEditingController(),
      characters: const [],
    );

    expect(find.text('还没有人物卡'), findsOneWidget);
  });

  testWidgets('有人物卡但都没命中时给出下一步', (tester) async {
    await _pumpStrip(
      tester,
      outline: TextEditingController(),
      content: TextEditingController(),
      characters: [_character(id: 'c1', name: '沈砚')],
    );

    expect(find.text('章纲和正文里还没出现任何人物卡上的名字'), findsOneWidget);
    expect(find.text('先写章纲，出场人物会自动对到人物卡上'), findsOneWidget);
  });
}
