// 职责: chapter_cast 出场扫描与人物首次落位的单元测试
// 关联文件: lib/shared/services/chapter_cast.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/chapter.dart';
import 'package:reveric/shared/models/character_profile.dart';
import 'package:reveric/shared/services/chapter_cast.dart';

CharacterProfile _character({
  required String id,
  required String name,
  List<String> aliases = const [],
}) {
  final now = DateTime(2026, 11, 22);
  return CharacterProfile(
    id: id,
    name: name,
    role: characterRoleSupporting,
    gender: characterGenderUnknown,
    aliases: aliases,
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

Chapter _chapter({
  required String id,
  required int chapterNum,
  String title = '',
  String outline = '',
  String content = '',
}) {
  final now = DateTime(2026, 11, 22);
  return Chapter(
    id: id,
    type: nodeTypeChapter,
    siblingOrder: chapterNum,
    title: title,
    outline: outline,
    content: content,
    chapterNum: chapterNum,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}

void main() {
  group('castTermsOf', () {
    test('人物名与别名都收，单字与空白被丢弃', () {
      final character = _character(
        id: 'c1',
        name: '沈砚',
        aliases: const ['砚哥', '', '  ', '王'],
      );
      expect(castTermsOf(character), ['沈砚', '砚哥']);
    });

    test('重复别名不重复计入', () {
      final character = _character(
        id: 'c1',
        name: '沈砚',
        aliases: const ['沈砚', '砚哥'],
      );
      expect(castTermsOf(character), ['沈砚', '砚哥']);
    });
  });

  group('countTermMentions', () {
    test('按出现次数计数', () {
      expect(countTermMentions('沈砚进门，沈砚坐下，砚哥笑了', ['沈砚', '砚哥']), 3);
    });

    test('长词优先，避免「沈砚」重复计入「沈砚舟」', () {
      expect(countTermMentions('沈砚舟来了', ['沈砚', '沈砚舟']), 1);
    });

    test('空文本或空词表返回 0', () {
      expect(countTermMentions('', ['沈砚']), 0);
      expect(countTermMentions('沈砚来了', const []), 0);
    });
  });

  group('scanChapterCast', () {
    test('章纲与正文分别计数，正文命中排在前面', () {
      final characters = [
        _character(id: 'c1', name: '沈砚', aliases: const ['砚哥']),
        _character(id: 'c2', name: '柳七'),
        _character(id: 'c3', name: '未登场的人'),
      ];
      final chapter = _chapter(
        id: 'ch1',
        chapterNum: 1,
        outline: '沈砚登场，柳七旁观',
        content: '柳七先开口，柳七又说了一句，砚哥没有回答。',
      );

      final hits = scanChapterCast(chapter: chapter, characters: characters);

      expect(hits.length, 2);
      expect(hits.first.characterName, '柳七');
      expect(hits.first.outlineMentions, 1);
      expect(hits.first.contentMentions, 2);

      final shen = hits[1];
      expect(shen.characterName, '沈砚');
      expect(shen.outlineMentions, 1);
      expect(shen.contentMentions, 1); // 命中别名「砚哥」
      expect(shen.terms, contains('砚哥'));
    });

    test('只在场但没有任何命中时不返回', () {
      final hits = scanChapterCast(
        chapter: _chapter(id: 'ch2', chapterNum: 2, content: '空镜。'),
        characters: [_character(id: 'c1', name: '沈砚')],
      );
      expect(hits, isEmpty);
    });
  });

  group('firstAppearanceChapterOf', () {
    test('正文命中优先于章纲命中：正文首章为 ch3，不退回章纲的 ch1', () {
      final character = _character(
        id: 'c1',
        name: '沈砚',
        aliases: const ['砚哥'],
      );
      final chapters = [
        _chapter(id: 'ch3', chapterNum: 3, content: '砚哥推门而入。'),
        _chapter(id: 'ch1', chapterNum: 1, outline: '沈砚的名字出现在章纲里'),
        _chapter(id: 'ch2', chapterNum: 2, outline: '柳七独白'),
      ];

      final first = firstAppearanceChapterOf(
        character: character,
        chapters: chapters,
      );

      expect(first?.id, 'ch3');
    });

    test('只有章纲命中时，退回章纲里最早的章节', () {
      final character = _character(id: 'c1', name: '沈砚');
      final chapters = [
        _chapter(id: 'ch7', chapterNum: 7, outline: '沈砚在第七章被提到'),
        _chapter(id: 'ch4', chapterNum: 4, outline: '沈砚在第四章被提到'),
      ];

      final first = firstAppearanceChapterOf(
        character: character,
        chapters: chapters,
      );

      expect(first?.id, 'ch4');
    });

    test('正文命中时按章节序号取最早，而不是列表顺序', () {
      final character = _character(id: 'c1', name: '沈砚');
      final chapters = [
        _chapter(id: 'ch9', chapterNum: 9, content: '沈砚在第九章'),
        _chapter(id: 'ch2', chapterNum: 2, content: '沈砚在第二章'),
      ];

      final first = firstAppearanceChapterOf(
        character: character,
        chapters: chapters,
      );

      expect(first?.id, 'ch2');
    });

    test('全文都没有出现时返回 null', () {
      final first = firstAppearanceChapterOf(
        character: _character(id: 'c1', name: '沈砚'),
        chapters: [_chapter(id: 'ch1', chapterNum: 1, content: '空镜。')],
      );
      expect(first, isNull);
    });
  });

  group('appearanceChapterCounts', () {
    test('按章统计，章纲或正文任一命中即算一章', () {
      final characters = [
        _character(id: 'c1', name: '沈砚'),
        _character(id: 'c2', name: '柳七'),
      ];
      final chapters = [
        _chapter(id: 'ch1', chapterNum: 1, outline: '沈砚到访', content: '沈砚到访'),
        _chapter(id: 'ch2', chapterNum: 2, content: '柳七独坐'),
        _chapter(id: 'ch3', chapterNum: 3, content: '沈砚与柳七对坐'),
      ];

      final counts = appearanceChapterCounts(
        chapters: chapters,
        characters: characters,
      );

      expect(counts['c1'], 2);
      expect(counts['c2'], 2);
    });
  });
}
