// 职责: 写章前的「本章上下文白名单」——按固定预算（12k 字符）从设定库挑出这一章真正要用的内容。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart（「写本章」时构建并随消息发送）
//   lib/desktop/pages/novel_editor.dart（把引用塞进 handoff 草稿）
//   lib/shared/services/ai/chat_prompt_builder.dart（引用按 file 类型内联进模型输入）
//   lib/shared/models/novel_workspace.dart（AiContextReference）
//   assets/bundled_skills/chapter-write-pipeline/SKILL.md（第 2 步「只喂本章所需的上下文」）
//
// 为什么要有这个文件：
//   之前写章时模型只能自己调工具去读设定，读不读、读多少全凭自觉；一旦没读，
//   角色、伏笔、世界观就全部退化成模型的自由发挥——复验里"两个人物凭空改名、
//   设定四表全空"就是这么来的。这里把"该给什么"变成确定性的代码：
//   预算固定、优先级固定、超了就按优先级裁，模型不需要也不允许自己再猜。
//
// 遵循的 Rules:
//   .agents/rules/i18n.md（对外文案走 LocaleKeys；本文件的正文是给模型吃的资料，不翻译）
import '../database/app_database.dart';
import '../database/novel_content_database.dart';
import '../models/chapter.dart';
import '../models/novel_workspace.dart';
import 'ai_exclusion.dart';
import 'novel_goal.dart';
import 'novel_style.dart';

/// 写章上下文的硬预算（按字符数计，中文 1 字 = 1 字符）。
const int chapterBriefingMaxCharacters = 12000;

/// 各段预算上限，加起来略大于总预算，最后再按优先级整体裁。
const int _outlineBudget = 2400;
const int _previousTailBudget = 1600;
const int _descriptionBudget = 400;
const int _characterItemCap = 700;
const int _loreItemCap = 500;
const int _foreshadowItemCap = 260;

/// 「写本章」时构造一条可随消息发送的上下文引用。
///
/// 用 [AiContextReferenceKind.file] 而不是 workspace：file 类型的内容会被
/// [AiPromptService] 直接内联进模型输入，不需要模型再发起读工具；
/// 预算已经在构建时裁好，模型拿到的是"刚好这一章够用"的设定切片。
AiContextReference buildChapterBriefingReference({
  required Novel novel,
  required Chapter chapter,
  required List<Chapter> chapters,
  required List<CharacterProfile> characters,
  required List<Document> lore,
  required List<Foreshadowing> foreshadowings,
  required String label,
  NovelGoal? goal,
  String? styleSample,
}) {
  return AiContextReference.file(
    itemId: 'chapter_briefing_${chapter.id}',
    label: label,
    content: buildChapterBriefing(
      novel: novel,
      chapter: chapter,
      chapters: chapters,
      characters: characters,
      lore: lore,
      foreshadowings: foreshadowings,
      goal: goal,
      styleSample: styleSample,
    ),
  );
}

/// 「按目标排章」时构造的上下文：整本书的规划视角，而不是某一章的切片。
///
/// 与写章上下文分开的原因：写章要"收窄到这章够用的设定"，排章正好相反，
/// 要给的是全书盘点——目标、已有章节与章纲、角色、世界观、未收伏笔，
/// 让模型知道自己接在第几章、后面还有多少空间，而不是凭空再开一条线。
AiContextReference buildPlanChaptersBriefingReference({
  required Novel novel,
  required List<Chapter> chapters,
  required List<CharacterProfile> characters,
  required List<Document> lore,
  required List<Foreshadowing> foreshadowings,
  required String label,
  NovelGoal? goal,
  String? styleSample,
}) {
  final buffer = StringBuffer()
    ..writeln('以下是本书的规划盘点（排章必须基于它，不要另起设定）。')
    ..writeln();

  final goalLine = novelGoalPromptLine(goal);
  if (goalLine.isNotEmpty) {
    buffer
      ..writeln(goalLine)
      ..writeln();
  }

  final styleSection = novelStylePromptSection(styleSample);
  if (styleSection.isNotEmpty) {
    buffer
      ..writeln(styleSection)
      ..writeln();
  }

  final description = novel.description.trim();
  if (description.isNotEmpty) {
    buffer
      ..writeln('## 作品简介')
      ..writeln(_clip(description, _descriptionBudget))
      ..writeln();
  }

  final bodies = chapters.where((chapter) => !chapter.isVolume).toList()
    ..sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));
  if (bodies.isNotEmpty) {
    buffer.writeln('## 已有章节（按顺序，含章纲开头，便于接着写而不是重写）');
    for (var i = 0; i < bodies.length; i++) {
      final chapter = bodies[i];
      final outline = chapter.outline.trim();
      buffer.writeln(
        '${i + 1}. ${chapter.title}'
        '${outline.isEmpty ? '（无章纲）' : '：${_clip(outline, 160)}'}',
      );
      if (buffer.length > 4000) {
        buffer.writeln('…（后续章节从略）');
        break;
      }
    }
    buffer.writeln();
  }

  if (characters.isNotEmpty) {
    final visible = characters
        .where((profile) => !isExcludedFromAi(profile.tags))
        .toList();
    if (visible.isNotEmpty) {
      buffer.writeln('## 主要角色');
      for (final profile in visible.take(12)) {
        final name = profile.name.trim();
        if (name.isEmpty) continue;
        final identity = profile.identity.trim();
        buffer.writeln(
          '- $name${identity.isEmpty ? '' : '（${_clip(identity, 30)}）'}'
          '${profile.currentState.trim().isEmpty ? '' : '：${_clip(profile.currentState, 120)}'}',
        );
      }
      buffer.writeln();
    }
  }

  if (lore.isNotEmpty) {
    buffer.writeln('## 世界观要点');
    for (final entry in lore.take(12)) {
      buffer.writeln('- ${entry.title}：${_clip(entry.content, 120)}');
    }
    buffer.writeln();
  }

  final open = _openForeshadowings(foreshadowings);
  if (open.isNotEmpty) {
    buffer.writeln('## 未回收伏笔（排章时要在后续章节给回收窗口）');
    for (final item in open.take(12)) {
      buffer.writeln('- ${item.title}');
    }
    buffer.writeln();
  }

  return AiContextReference.file(
    itemId: 'plan_chapters_${novel.id}',
    label: label,
    content: _fitBudget(buffer.toString()),
  );
}

/// 「沉淀本章」时构造引用：把本章正文原文交给模型，回填必须基于真实文本。
AiContextReference buildChapterSettleReference({
  required Chapter chapter,
  required String label,
}) {
  final body = _clip(chapter.content.trim(), chapterBriefingMaxCharacters - 600);
  final content = StringBuffer()
    ..writeln('以下是本章正文原文（沉淀必须基于它，不要凭印象补写）。')
    ..writeln()
    ..writeln(body);
  return AiContextReference.file(
    itemId: 'chapter_settle_${chapter.id}',
    label: label,
    content: content.toString(),
  );
}

/// 组装本章上下文正文。段落按优先级排列，最后统一裁到 [chapterBriefingMaxCharacters]。
String buildChapterBriefing({
  required Novel novel,
  required Chapter chapter,
  required List<Chapter> chapters,
  required List<CharacterProfile> characters,
  required List<Document> lore,
  required List<Foreshadowing> foreshadowings,
  NovelGoal? goal,
  String? styleSample,
}) {
  final buffer = StringBuffer()
    ..writeln('以下是本次写章可用的全部设定（由软件按本章需要挑选，未列出的内容不要自行编造）。')
    ..writeln();

  final goalLine = novelGoalPromptLine(goal);
  if (goalLine.isNotEmpty) {
    buffer
      ..writeln(goalLine)
      ..writeln();
  }

  final styleSection = novelStylePromptSection(styleSample);
  if (styleSection.isNotEmpty) {
    buffer
      ..writeln(styleSection)
      ..writeln();
  }

  // ── 优先级 1：本章章纲 / 简报 ───────────────────────────────
  final outline = chapter.outline.trim();
  final brief = chapter.brief.trim();
  if (outline.isNotEmpty || brief.isNotEmpty) {
    buffer.writeln('## 本章要写的内容');
    if (outline.isNotEmpty) {
      buffer
        ..writeln('章纲：')
        ..writeln(_clip(outline, _outlineBudget))
        ..writeln();
    }
    if (brief.isNotEmpty) {
      buffer
        ..writeln('写前简报：')
        ..writeln(_clip(brief, 800))
        ..writeln();
    }
  }

  // ── 优先级 2：上一章结尾（承接语气与未收的钩子）────────────
  final previous = _previousBodyChapter(chapter, chapters);
  final previousTail = previous?.content.trim() ?? '';
  if (previousTail.isNotEmpty) {
    buffer
      ..writeln('## 上一章结尾（只用于承接，不要重复）')
      ..writeln(_tail(previousTail, _previousTailBudget))
      ..writeln();
  }

  // ── 优先级 3：作品简介 ─────────────────────────────────────
  final description = novel.description.trim();
  if (description.isNotEmpty) {
    buffer
      ..writeln('## 作品简介')
      ..writeln(_clip(description, _descriptionBudget))
      ..writeln();
  }

  // ── 优先级 4：本章相关角色（章纲里出现的优先）──────────────
  final matched = _charactersForChapter(outline, characters);
  if (matched.isNotEmpty) {
    buffer.writeln('## 本章相关角色档案（不得改名、不得改身份）');
    for (final profile in matched) {
      buffer
        ..writeln('### ${profile.name}${profile.identity.trim().isEmpty ? '' : '（${_clip(profile.identity, 40)}）'}')
        ..writeln(_characterBlock(profile))
        ..writeln();
    }
  }

  // ── 优先级 5：世界观规则 ────────────────────────────────────
  final loreEntries = _loreForChapter(outline, lore);
  if (loreEntries.isNotEmpty) {
    buffer.writeln('## 世界观设定（与正文冲突时以此为准）');
    for (final entry in loreEntries) {
      buffer
        ..writeln('- ${entry.title}：${_clip(entry.content, _loreItemCap)}');
    }
    buffer.writeln();
  }

  // ── 优先级 6：未收伏笔 ────────────────────────────────────
  final open = _openForeshadowings(foreshadowings);
  if (open.isNotEmpty) {
    buffer.writeln('## 未回收伏笔（该埋则埋，该收则收，别凭空新增）');
    for (final item in open) {
      final setup = item.setup.trim();
      final payoff = item.payoff.trim();
      buffer.writeln(
        '- ${item.title}'
        '${setup.isEmpty ? '' : '（埋设：${_clip(setup, _foreshadowItemCap)}）'}'
        '${payoff.isEmpty ? '' : '（回收：${_clip(payoff, _foreshadowItemCap)}）'}',
      );
    }
    buffer.writeln();
  }

  return _fitBudget(buffer.toString());
}

/// 本章之前、最近一个有正文的普通章节（跳过卷）。
Chapter? _previousBodyChapter(Chapter target, List<Chapter> chapters) {
  final bodies = chapters
      .where((item) => !item.isVolume && item.id != target.id)
      .toList()
    ..sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));
  Chapter? fallback;
  for (final item in bodies) {
    if (item.content.trim().isEmpty) continue;
    if (item.siblingOrder < target.siblingOrder) return item;
    fallback ??= item;
  }
  return fallback;
}

/// 章纲里点名过的角色先上，不足再按角色档案顺序补足（最多 6 个）。
///
/// 标了「不进AI」的角色一律不进来：作者的私房设定不该被模型带进正文。
List<CharacterProfile> _charactersForChapter(
  String outline,
  List<CharacterProfile> characters,
) {
  final pool = characters
      .where((profile) => !isExcludedFromAi(profile.tags))
      .toList();
  if (pool.isEmpty) return const [];
  final matched = <CharacterProfile>[];
  for (final profile in pool) {
    final name = profile.name.trim();
    if (name.isEmpty) continue;
    if (outline.contains(name)) matched.add(profile);
  }
  for (final profile in pool) {
    if (matched.length >= 6) break;
    if (!matched.contains(profile)) matched.add(profile);
  }
  return matched.take(6).toList();
}

String _characterBlock(CharacterProfile profile) {
  final parts = <String>[];
  void add(String label, String value) {
    final text = value.trim();
    if (text.isNotEmpty) parts.add('$label：${_clip(text, _characterItemCap)}');
  }

  add('身份', profile.identity);
  add('年龄', profile.age);
  add('当前状态', profile.currentState);
  add('人物档案', profile.biography);
  return parts.join('\n');
}

/// 世界观条目按标题命中章纲优先，其次按顺序（最多 8 条）。
List<Document> _loreForChapter(String outline, List<Document> lore) {
  if (lore.isEmpty) return const [];
  final matched = <Document>[];
  for (final entry in lore) {
    if (entry.isFolder) continue;
    final title = entry.title.trim();
    if (title.isEmpty) continue;
    if (outline.contains(title)) matched.add(entry);
  }
  for (final entry in lore) {
    if (matched.length >= 8) break;
    if (entry.isFolder) continue;
    if (!matched.contains(entry)) matched.add(entry);
  }
  return matched.take(8).toList();
}

List<Foreshadowing> _openForeshadowings(List<Foreshadowing> items) {
  final open = items.where((item) {
    final status = item.status.trim().toLowerCase();
    return status.isEmpty || status != 'resolved';
  }).toList();
  return open.take(8).toList();
}

/// 总预算裁剪：超了就按段落优先级从后往前砍。
String _fitBudget(String text) {
  if (text.runes.length <= chapterBriefingMaxCharacters) return text;
  final sections = text.split('\n## ');
  final buffer = StringBuffer(sections.first.trimRight());
  var length = sections.first.runes.length;
  for (var i = 1; i < sections.length; i++) {
    final section = '\n## ${sections[i]}';
    final sectionLength = section.runes.length;
    if (length + sectionLength > chapterBriefingMaxCharacters) {
      final remaining = chapterBriefingMaxCharacters - length;
      if (remaining > 200) {
        buffer.write(_clip(section, remaining));
      }
      break;
    }
    buffer.write(section);
    length += sectionLength;
  }
  return buffer.toString();
}

String _clip(String text, int limit) {
  final normalized = text.replaceAll(RegExp(r'[ \t]+\n'), '\n').trim();
  final runes = normalized.runes.toList();
  if (runes.length <= limit) return normalized;
  final head = String.fromCharCodes(runes.take(limit - 1));
  return '$head…';
}

String _tail(String text, int limit) {
  final runes = text.runes.toList();
  if (runes.length <= limit) return text;
  final tail = String.fromCharCodes(runes.sublist(runes.length - limit + 1));
  return '…$tail';
}
