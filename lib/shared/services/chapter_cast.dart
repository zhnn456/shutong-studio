// 职责: 出场人物扫描与人物首次落位（纯确定性匹配，不依赖 AI 输出格式）
// 关联文件:
//   lib/shared/models/chapter.dart
//   lib/shared/models/character_profile.dart
//   lib/desktop/widgets/workspace/character_profile_editor.dart（人物卡「本作首次出场」落位）
//
// 设计约束:
//   1. 只读文本、不写库。落库由调用方（人物卡按钮）调用
//      updateCharacterFirstAppearChapter，避免本层出现隐式副作用。
//   2. 匹配词 = 人物名 + 全部别名；长度小于 2 的词（单字）不参与，
//      避免「王」「李」这类单字误命中。
//   3. 长词优先并遮蔽已命中区间，避免「李明」把「李明远」的命中重复计数。

import '../models/chapter.dart';
import '../models/character_profile.dart';

/// 单章里某个角色的出场情况。
class ChapterCastHit {
  const ChapterCastHit({
    required this.character,
    required this.terms,
    required this.outlineMentions,
    required this.contentMentions,
  });

  final CharacterProfile character;

  /// 实际命中的词（人物名或别名）。
  final List<String> terms;

  final int outlineMentions;
  final int contentMentions;

  String get characterId => character.id;
  String get characterName => character.name;

  int get totalMentions => outlineMentions + contentMentions;

  /// 是否已在正文里出现（章纲里出现但正文未写不算）。
  bool get appearsInBody => contentMentions > 0;

  @override
  String toString() =>
      'ChapterCastHit(${character.name}, outline=$outlineMentions, '
      'content=$contentMentions)';
}

/// 归一化匹配词：去空、去重、丢弃单字（`王` 这类单字会把整本书都点亮）。
List<String> normalizeCastTerms(Iterable<String> raw) {
  final terms = <String>[];
  for (final item in raw) {
    final term = item.trim();
    if (term.isEmpty || term.runes.length < 2 || terms.contains(term)) {
      continue;
    }
    terms.add(term);
  }
  return terms;
}

/// 提取一个角色的匹配词：人物名 + 别名。
List<String> castTermsOf(CharacterProfile character) =>
    normalizeCastTerms([character.name, ...character.aliases]);

/// 统计 [terms] 在 [text] 中的出现次数：长词优先，命中后遮蔽区间避免重叠计数。
int countTermMentions(String text, List<String> terms) {
  if (text.isEmpty || terms.isEmpty) {
    return 0;
  }
  final ordered = [...terms]
    ..sort((a, b) => b.length.compareTo(a.length));
  var working = text;
  var total = 0;
  for (final term in ordered) {
    if (term.isEmpty) {
      continue;
    }
    var index = working.indexOf(term);
    var hits = 0;
    while (index >= 0) {
      hits += 1;
      // 用同长度的占位符遮蔽，保持后续 indexOf 的下标语义不变。
      working = working.replaceRange(
        index,
        index + term.length,
        '\u0000' * term.length,
      );
      index = working.indexOf(term);
    }
    total += hits;
  }
  return total;
}

/// 扫描单章的出场人物，返回按出场强度（正文优先、命中次数）降序的结果。
List<ChapterCastHit> scanChapterCast({
  required Chapter chapter,
  required List<CharacterProfile> characters,
}) {
  final hits = <ChapterCastHit>[];
  for (final character in characters) {
    final terms = castTermsOf(character);
    if (terms.isEmpty) {
      continue;
    }
    final outlineMentions = countTermMentions(chapter.outline, terms);
    final contentMentions = countTermMentions(chapter.content, terms);
    if (outlineMentions == 0 && contentMentions == 0) {
      continue;
    }
    final matched = <String>[
      for (final term in terms)
        if (chapter.content.contains(term) || chapter.outline.contains(term))
          term,
    ];
    hits.add(
      ChapterCastHit(
        character: character,
        terms: matched,
        outlineMentions: outlineMentions,
        contentMentions: contentMentions,
      ),
    );
  }
  hits.sort((a, b) {
    if (a.appearsInBody != b.appearsInBody) {
      return a.appearsInBody ? -1 : 1;
    }
    return b.totalMentions.compareTo(a.totalMentions);
  });
  return hits;
}

/// 章节在书里的先后顺序：优先章节序号，其次兄弟顺序。
int chapterOrderOf(Chapter chapter) =>
    chapter.chapterNum ?? chapter.siblingOrder;

/// 只按匹配词扫章节：正文命中优先，其次退回章纲命中，卷节点不参与。
Chapter? firstChapterMatchingTerms({
  required List<String> terms,
  required List<Chapter> chapters,
}) {
  if (terms.isEmpty) {
    return null;
  }
  final sorted = [
    for (final chapter in chapters)
      if (!chapter.isVolume) chapter,
  ]..sort((a, b) => chapterOrderOf(a).compareTo(chapterOrderOf(b)));
  for (final chapter in sorted) {
    if (countTermMentions(chapter.content, terms) > 0) {
      return chapter;
    }
  }
  for (final chapter in sorted) {
    if (countTermMentions(chapter.outline, terms) > 0) {
      return chapter;
    }
  }
  return null;
}

/// 一条角色线索在多少章里出现过（章纲或正文任一命中即算一章，卷节点不参与）。
int countChaptersMatchingTerms({
  required List<String> terms,
  required List<Chapter> chapters,
}) {
  if (terms.isEmpty) {
    return 0;
  }
  var count = 0;
  for (final chapter in chapters) {
    if (chapter.isVolume) {
      continue;
    }
    if (countTermMentions(chapter.outline, terms) > 0 ||
        countTermMentions(chapter.content, terms) > 0) {
      count += 1;
    }
  }
  return count;
}

/// 找出角色在全书正文里首次出现的章节（正文优先；正文没写才退回章纲）。
Chapter? firstAppearanceChapterOf({
  required CharacterProfile character,
  required List<Chapter> chapters,
}) {
  return firstChapterMatchingTerms(
    terms: castTermsOf(character),
    chapters: chapters,
  );
}

/// 统计每个角色各自出现在多少章（章纲或正文任一命中即算一章）。
Map<String, int> appearanceChapterCounts({
  required List<Chapter> chapters,
  required List<CharacterProfile> characters,
}) {
  final counts = <String, int>{};
  for (final character in characters) {
    counts[character.id] = countChaptersMatchingTerms(
      terms: castTermsOf(character),
      chapters: chapters,
    );
  }
  return counts;
}
