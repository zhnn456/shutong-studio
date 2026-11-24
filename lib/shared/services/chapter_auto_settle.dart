// 职责: 正文保存后由纯代码生成"沉淀"数据（梗概 / 章内事件 / 张力 / 情绪 / 出场人物 / 章末钩子）。
// 关联文件:
//   lib/shared/services/text_summary/chinese_summary.dart（摘要引擎，移植自 MIT 上游）
//   lib/shared/services/novel_content.dart（保存正文后调用）
//   docs/chapter-auto-settle-log.md（设计、算法来源、回滚）
//
// 设计原则：
//   1. 不调 AI、不联网、零依赖。只用 chinese_summary 的 TextRank + MMR 选句，
//      把"本章真正写过的句子"搬进梗概，不做任何改写，因此不会出现幻觉或 AI 腔。
//   2. 只做可核查的事实搬运：选了哪几句、哪几个人物出现、结尾停在哪。
//      需要文学化总结时仍走 chronicler（AI），两者互不覆盖。
//   3. 全部是确定性函数：同一份正文永远得到同一份结果，便于回归测试与回滚。

import 'text_summary/chinese_summary.dart';

/// 算法版本。改动选句参数或字段含义时必须 +1，否则已沉淀章节不会重算。
const String chapterAutoSettleVersion = 'auto_settle.v1';

/// 低于这个字数的正文不值得沉淀（还没写成一段完整的戏）。
const int chapterAutoSettleMinWords = 400;

/// 冲突/推进词表：出现即视为"这一句在推事情"，提权。
const List<String> _conflictWords = <String>[
  '却', '但', '突然', '忽然', '终于', '决定', '发现', '原来', '必须', '不能',
  '拒绝', '答应', '威胁', '杀', '死', '逃', '追', '打', '抢', '夺', '刺',
  '背叛', '出卖', '秘密', '真相', '骗', '赌', '换', '断', '毁', '救',
  '逼', '怒', '狂', '跪', '废', '夺回', '翻脸', '撕', '塌', '爆', '炸',
  '开战', '宣战', '投降', '反悔', '追查', '揭露', '认输', '低头', '吐血',
];

/// 情绪词表（2–4 字标签）。按出现次数取前 2。
const Map<String, String> _emotionLexicon = <String, String>{
  '怒': '愤怒', '恨': '怨恨', '怕': '恐惧', '慌': '慌乱', '哭': '悲恸',
  '笑': '轻松', '冷': '冷冽', '沉': '沉重', '紧': '紧绷', '暖': '温热',
  '疼': '痛楚', '寒': '寒意', '血': '血腥', '杀': '杀意', '逃': '绝境',
  '等': '等待', '忍': '隐忍', '愧': '愧疚', '羞': '屈辱', '狂': '狂热',
};

/// 章内事件条目（写进 `chapter_nodes.events`，结构沿用现有展示卡片）。
///
/// 字段名与既有 chronicler 产物保持一致：title / summary / state_change。
Map<String, dynamic> buildSettledEvent({
  required String title,
  required String summary,
  required String stateChange,
}) {
  return <String, dynamic>{
    'title': title,
    'summary': summary,
    'state_change': stateChange,
  };
}

/// 一次沉淀的结果。全部字段都可以直接落库。
class ChapterSettlement {
  const ChapterSettlement({
    required this.brief,
    required this.events,
    required this.tension,
    required this.emotions,
    required this.cast,
    required this.hook,
    required this.selectedSentenceCount,
    required this.signature,
  });

  /// 整章梗概：抽取的高分句按原文顺序拼接。
  final String brief;

  /// 章内事件：按段落取最高分句，2–6 条。
  final List<Map<String, dynamic>> events;

  /// 紧张度 1–10。
  final int tension;

  /// 情绪标签（2 个以内）。
  final List<String> emotions;

  /// 本章出现的已知人物名。
  final List<String> cast;

  /// 章末钩子：最后一句话，截断到 60 字。
  final String hook;

  /// 实际选入梗概的句数，便于作者判断"这段总结是靠不靠得住"。
  final int selectedSentenceCount;

  /// 内容指纹（用于判断"梗概是不是自动生成的、要不要重算"）。
  final String signature;
}

/// 判断正文是否值得沉淀。
bool shouldAutoSettle(String content) {
  final cleaned = content.replaceAll(RegExp(r'\s+'), '');
  return cleaned.length >= chapterAutoSettleMinWords;
}

/// 判断一段已有的 brief 是不是"从本章正文抽出来的"（即本模块自己生成的）。
///
/// 依据：抽取式梗概由原文句子拼接，所以绝大部分句子能在正文里原样找到；
/// AI 或作者写的梗概会改写、缩写，命中率会明显低于 60%。
/// 这样不需要额外存"谁写的"状态，也能避免覆盖人工成果。
bool briefLooksExtracted(String brief, String content) {
  final sentences = splitSentences(brief, minSentenceLength: 5);
  if (sentences.isEmpty) return false;
  final haystack = content.replaceAll(RegExp(r'\s+'), '');
  var hits = 0;
  for (final sentence in sentences) {
    final needle = sentence.text.replaceAll(RegExp(r'\s+'), '');
    if (needle.length >= 5 && haystack.contains(needle)) hits++;
  }
  return hits / sentences.length >= 0.6;
}

/// 内容指纹：字数 + 首尾片段 + 版本号。足够区分"内容是否变了"，
/// 不需要哈希库（避免为一个指纹引入依赖）。
String chapterSignature(String content) {
  final normalized = content.replaceAll(RegExp(r'\s+'), '');
  final head = normalized.length <= 40
      ? normalized
      : normalized.substring(0, 40);
  final tail = normalized.length <= 20
      ? normalized
      : normalized.substring(normalized.length - 20);
  return '$chapterAutoSettleVersion:${normalized.length}:$head::$tail';
}

/// 生成沉淀结果。
///
/// [knownNames] 传当前人物卡的名字与别名，用于统计本章出场；没有传就不做统计。
ChapterSettlement? settleChapter(
  String content, {
  List<String> knownNames = const <String>[],
  SummaryOptions options = const SummaryOptions(),
}) {
  if (!shouldAutoSettle(content)) return null;

  final sentences = splitSentences(content, minSentenceLength: 5);
  if (sentences.isEmpty) return null;

  final ngramSets = <Set<String>>[];
  for (final sentence in sentences) {
    ngramSets.add(extractNgrams(sentence.text, options.ngramSize));
  }
  final keywords = extractKeywords(sentences, 20);
  textRank(sentences, ngramSets, options, keywords: keywords);

  // 梗概目标字数约 200：按平均句长换算句数，兜在 2–6 句之间。
  final averageLength =
      sentences.map((sentence) => sentence.text.length).reduce((a, b) => a + b) /
          sentences.length;
  final targetSentences =
      (200 / (averageLength <= 0 ? 20 : averageLength)).round().clamp(2, 6);
  final summary = selectByMmr(
    sentences,
    ngramSets,
    targetSentences,
    options.mmrLambda,
  );

  final brief = summary
      .map((sentence) => sentence.text)
      .join('')
      .replaceAll(RegExp(r'\s+'), '');

  // 章内事件：每段取该段得分最高的句子；只有一段时取前两句 + 末句。
  final byParagraph = <int, List<SummarySentence>>{};
  for (final sentence in sentences) {
    byParagraph.putIfAbsent(sentence.paragraphIndex, () => <SummarySentence>[])
        .add(sentence);
  }

  final events = <Map<String, dynamic>>[];
  final paragraphs = byParagraph.keys.toList()..sort();
  for (final paragraphIndex in paragraphs) {
    final inParagraph = byParagraph[paragraphIndex]!;
    final top = inParagraph.reduce(
      (a, b) => a.score >= b.score ? a : b,
    );
    final title = _eventTitle(top.text);
    final stateChange = _stateChangeOf(top.text);
    events.add(
      buildSettledEvent(
        title: title,
        summary: _clip(top.text, 90),
        stateChange: stateChange,
      ),
    );
    if (events.length >= 6) break;
  }

  // 一段都切不出来时，退回"前两句 + 最后一句"。
  if (events.isEmpty) {
    for (final sentence in <SummarySentence>[
      ...sentences.take(2),
      sentences.last,
    ]) {
      events.add(
        buildSettledEvent(
          title: _eventTitle(sentence.text),
          summary: _clip(sentence.text, 90),
          stateChange: _stateChangeOf(sentence.text),
        ),
      );
    }
  }

  final hook = _clip(sentences.last.text, 60);
  final cast = _castOf(content, knownNames);

  return ChapterSettlement(
    brief: brief,
    events: events,
    tension: _tensionOf(content, sentences, summary),
    emotions: _emotionsOf(content, sentences),
    cast: cast,
    hook: hook,
    selectedSentenceCount: summary.length,
    signature: chapterSignature(content),
  );
}

String _clip(String text, int maxLength) {
  final normalized = text.replaceAll(RegExp(r'\s+'), '').trim();
  if (normalized.length <= maxLength) return normalized;
  return '${normalized.substring(0, maxLength)}…';
}

/// 事件标题：取第一个子句，去掉开头的人称与语气词。
String _eventTitle(String sentence) {
  final clauses = splitClauses(sentence, minLength: 3);
  final base = clauses.isNotEmpty ? clauses.first : sentence;
  var title = base.replaceAll(RegExp(r'\s+'), '');
  title = title.replaceFirst(RegExp(r'^[他她它我你咱]+'), '');
  title = title.replaceFirst(RegExp(r'^[的了是在，、]'), '');
  return _clip(title, 18);
}

/// 状态变化：句中出现"于是/从此/再也/决定/答应/只能/必须"等推进词时，
/// 把该子句原样当作状态变化；没有则留空，不编。
String _stateChangeOf(String sentence) {
  const markers = <String>[
    '于是', '从此', '再也', '决定', '答应', '只能', '必须', '不再',
    '终于', '转而', '改成', '改为',
  ];
  for (final clause in splitClauses(sentence, minLength: 4)) {
    for (final marker in markers) {
      if (clause.contains(marker)) {
        return _clip(clause, 40);
      }
    }
  }
  return '';
}

/// 紧张度：冲突词密度 × 感叹/问号密度 × 短句比例，映射到 1–10。
int _tensionOf(
  String content,
  List<SummarySentence> sentences,
  List<SummarySentence> summary,
) {
  final characters = content.replaceAll(RegExp(r'\s+'), '');
  if (characters.isEmpty) return 3;

  var conflictHits = 0;
  for (final word in _conflictWords) {
    conflictHits += _countOccurrences(content, word);
  }

  final exclamations = _countOccurrences(content, '！') +
      _countOccurrences(content, '？') +
      _countOccurrences(content, '…');
  final conflictDensity = conflictHits / (characters.length / 100.0);
  final punctuationDensity = exclamations / (characters.length / 100.0);

  var shortSentences = 0;
  for (final sentence in sentences) {
    if (sentence.text.length <= 15) shortSentences++;
  }
  final shortRatio = sentences.isEmpty ? 0 : shortSentences / sentences.length;

  var score = 2.0 +
      conflictDensity * 1.4 +
      punctuationDensity * 1.2 +
      shortRatio * 2.0;

  // 选中的句子是否明显高于全章中位数（说明这一章的高潮确实进了梗概）。
  if (summary.isNotEmpty) {
    final averageSummaryScore = summary
            .map((sentence) => sentence.score)
            .reduce((a, b) => a + b) /
        summary.length;
    final allScores = sentences.map((sentence) => sentence.score).toList()
      ..sort();
    final median = allScores[allScores.length ~/ 2];
    if (median > 0 && averageSummaryScore > median * 1.1) {
      score += 0.6;
    }
  }

  return score.round().clamp(1, 10);
}

/// 情绪：词表命中次数取前 2；一个都没中就按紧张度给中性标签。
List<String> _emotionsOf(String content, List<SummarySentence> sentences) {
  final counts = <String, int>{};
  for (final entry in _emotionLexicon.entries) {
    final count = _countOccurrences(content, entry.key);
    if (count > 0) {
      counts[entry.value] = (counts[entry.value] ?? 0) + count;
    }
  }
  if (counts.isEmpty) return const <String>[];
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries.take(2).map((entry) => entry.key).toList();
}

/// 出场人物：已知名字（含别名）在正文中出现，按出现次数排序取前 8。
List<String> _castOf(String content, List<String> knownNames) {
  if (knownNames.isEmpty) return const <String>[];
  final hits = <String, int>{};
  for (final name in knownNames) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) continue;
    final count = _countOccurrences(content, trimmed);
    if (count > 0) hits[trimmed] = count;
  }
  if (hits.isEmpty) return const <String>[];
  final entries = hits.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries.take(8).map((entry) => entry.key).toList();
}

int _countOccurrences(String text, String pattern) {
  if (pattern.isEmpty) return 0;
  var count = 0;
  var index = text.indexOf(pattern);
  while (index != -1) {
    count++;
    index = text.indexOf(pattern, index + pattern.length);
  }
  return count;
}
