// 职责: 中文抽取式摘要（TextRank + 位置加权 + TF-IDF + MMR）。
// 关联文件:
//   lib/shared/services/chapter_auto_settle.dart（唯一调用方）
//   third/upstreams/chinese-summary/（上游源码与 README，含 MIT 声明）
//   docs/chapter-auto-settle-log.md（移植范围与授权记录）
//
// 来源与授权（本文件不是自研算法）：
//   上游: cn-dev/chinese-summary 1.0.5（npm），MIT License
//   Copyright (c) 2025 北京锋通科技有限公司 / Authors: 郭玉峰, 吴琼
//   本文件是上述 TypeScript 实现的 Dart 移植，算法、参数默认值、公式均照上游：
//   - 分句：句末标点在 。！？；\n 处切分，句末引号归入前句
//   - 相似度：|A∩B| / (log(|A|+1) + log(|B|+1))，字级 n-gram（绕开中文分词）
//   - 关键词：字级 TF-IDF，IDF = log((n+1)/(df+1)) + 1
//   - 位置权重：首段首句 1.5 / 首段其余 1.2 / 段落首句 1.1 / 段落末句 1.05
//   - TextRank：WS = (1-d)·init + d·Σ(sim(i,j)/Σsim(j,k))·WS(j)，d=0.85，30 次迭代
//   - MMR：λ·score - (1-λ)·maxSim，λ=0.7
//
// 未移植的部分（上游 level 1 极致压缩与 level 2 多轮重排）：章节梗概需要的是
// 完整可读的若干句，而不是压成一句话，故这两个分支不引入。
//
// 修改约定：上游若升级算法，先更新 third/upstreams 再改这里，并在 log 文档
// 写明版本与差异；不要在没有上游依据的情况下改公式。

import 'dart:math' as math;

/// 摘要选项。字段名与上游 SummaryOptions 一一对应。
class SummaryOptions {
  const SummaryOptions({
    this.sentenceCount = 3,
    this.compressionLevel = 3,
    this.ngramSize = 2,
    this.dampingFactor = 0.85,
    this.maxIterations = 30,
    this.convergenceThreshold = 0.0001,
    this.weightFirstSentence = 1.5,
    this.weightFirstParagraph = 1.2,
    this.weightParagraphStart = 1.1,
    this.weightParagraphEnd = 1.05,
    this.minSentenceLength = 5,
    this.mmrLambda = 0.7,
    this.keywordWeight = 1.2,
  });

  /// 摘要句数。`compressionLevel` 为空时按此值定句数。
  final int sentenceCount;

  /// 1–5。3 表示约 30% 句子、最少 3 句。
  final int compressionLevel;

  final int ngramSize;
  final double dampingFactor;
  final int maxIterations;
  final double convergenceThreshold;
  final double weightFirstSentence;
  final double weightFirstParagraph;
  final double weightParagraphStart;
  final double weightParagraphEnd;
  final int minSentenceLength;
  final double mmrLambda;
  final double keywordWeight;
}

/// 句子及其位置信息与 TextRank 得分。
class SummarySentence {
  SummarySentence({
    required this.index,
    required this.text,
    required this.paragraphIndex,
    required this.sentenceInParagraph,
    required this.isParagraphStart,
    required this.isParagraphEnd,
    required this.isFirstParagraph,
    this.score = 0,
  });

  final int index;
  final String text;
  final int paragraphIndex;
  final int sentenceInParagraph;
  final bool isParagraphStart;
  final bool isParagraphEnd;
  final bool isFirstParagraph;
  double score;
}

/// 摘要结果。`summary` 已按原文顺序排列。
class SummaryResult {
  const SummaryResult({
    required this.summary,
    required this.sentences,
    required this.text,
    required this.compressionLevel,
  });

  final List<SummarySentence> summary;
  final List<SummarySentence> sentences;
  final String text;
  final int compressionLevel;
}

/// 中文句子结束标点（与上游 SENTENCE_ENDINGS 一致）。
const Set<String> _sentenceEndings = <String>{
  '。',
  '！',
  '？',
  '；',
  '\n',
  '\r',
};

/// 句末标点后可能紧跟的引号、括号，归入前一句。
const Set<String> _trailingQuotes = <String>{
  '」',
  '』',
  '\u201C',
  '\u201D',
  '）',
  '】',
  '》',
  '\u2018',
  '\u2019',
};

/// 中文停用字（上游 STOP_CHARS 原文）。
const String _stopChars =
    '的了是在我有和就不人都一这中大为上个国也子时道说出会要没成好能对然她过生里后以到去能得着年这';

const Set<String> _clauseSeparators = <String>{'，', '、', ',', '；', ';', '：', ':'};

/// 只保留汉字、字母、数字（与上游清洗正则等价）。
String _keepWordChars(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final isCjk = (rune >= 0x4e00 && rune <= 0x9fff) ||
        (rune >= 0x3400 && rune <= 0x4dbf) ||
        rune == 0x3007;
    final isAsciiWord = (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5a) ||
        (rune >= 0x61 && rune <= 0x7a);
    if (isCjk || isAsciiWord) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// 按段落与句末标点切句，过滤过短句。
List<SummarySentence> splitSentences(
  String text, {
  int minSentenceLength = 5,
}) {
  final sentences = <SummarySentence>[];
  final paragraphs = text
      .split(RegExp(r'[\n\r]+'))
      .where((paragraph) => paragraph.trim().isNotEmpty)
      .toList();

  var globalIndex = 0;
  for (var paragraphIndex = 0;
      paragraphIndex < paragraphs.length;
      paragraphIndex++) {
    final paragraph = paragraphs[paragraphIndex].trim();
    if (paragraph.isEmpty) continue;

    final raw = <String>[];
    final units = paragraph.codeUnits;
    var current = StringBuffer();

    for (var i = 0; i < units.length; i++) {
      final char = String.fromCharCode(units[i]);
      current.write(char);

      if (_sentenceEndings.contains(char)) {
        while (i + 1 < units.length &&
            _trailingQuotes.contains(String.fromCharCode(units[i + 1]))) {
          i++;
          current.write(String.fromCharCode(units[i]));
        }
        final trimmed = current.toString().trim();
        if (trimmed.isNotEmpty) raw.add(trimmed);
        current = StringBuffer();
      }
    }

    final rest = current.toString().trim();
    if (rest.isNotEmpty) raw.add(rest);

    for (var sentenceInParagraph = 0;
        sentenceInParagraph < raw.length;
        sentenceInParagraph++) {
      final sentence = raw[sentenceInParagraph];
      if (sentence.length < minSentenceLength) continue;
      sentences.add(
        SummarySentence(
          index: globalIndex++,
          text: sentence,
          paragraphIndex: paragraphIndex,
          sentenceInParagraph: sentenceInParagraph,
          isParagraphStart: sentenceInParagraph == 0,
          isParagraphEnd: sentenceInParagraph == raw.length - 1,
          isFirstParagraph: paragraphIndex == 0,
        ),
      );
    }
  }

  return sentences;
}

/// 字级 n-gram 集合。
Set<String> extractNgrams(String text, int n) {
  final cleaned = _keepWordChars(text);
  if (cleaned.length < n) return <String>{};
  final grams = <String>{};
  for (var i = 0; i <= cleaned.length - n; i++) {
    grams.add(cleaned.substring(i, i + n));
  }
  return grams;
}

/// 字级 TF-IDF 关键词（Top-K）。
Set<String> extractKeywords(List<SummarySentence> sentences, int topK) {
  if (sentences.isEmpty) return <String>{};

  final tf = <String, int>{};
  final df = <String, int>{};

  for (final sentence in sentences) {
    final cleaned = _keepWordChars(sentence.text);
    final seen = <String>{};
    for (final rune in cleaned.runes) {
      final char = String.fromCharCode(rune);
      if (_stopChars.contains(char)) continue;
      tf[char] = (tf[char] ?? 0) + 1;
      if (!seen.contains(char)) {
        df[char] = (df[char] ?? 0) + 1;
        seen.add(char);
      }
    }
  }

  final total = sentences.length;
  final tfidf = <String, double>{};
  tf.forEach((char, freq) {
    final docFreq = df[char] ?? 1;
    final idf = math.log((total + 1) / (docFreq + 1)) + 1;
    tfidf[char] = freq * idf;
  });

  final entries = tfidf.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries.take(topK).map((entry) => entry.key).toSet();
}

double _keywordWeightForSentence(
  SummarySentence sentence,
  Set<String> keywords,
  double keywordWeight,
) {
  if (keywords.isEmpty || keywordWeight == 0) return 1.0;
  final cleaned = _keepWordChars(sentence.text);
  var hits = 0;
  for (final rune in cleaned.runes) {
    if (keywords.contains(String.fromCharCode(rune))) hits++;
  }
  if (hits == 0) return 1.0;
  final ratio = hits / keywords.length;
  return math.pow(keywordWeight, math.min(ratio, 1.0)).toDouble();
}

/// 句子相似度：|A∩B| / (log(|A|+1) + log(|B|+1))。
double similarity(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var intersection = 0;
  for (final gram in a) {
    if (b.contains(gram)) intersection++;
  }
  if (intersection == 0) return 0;
  final denominator = math.log(a.length + 1) + math.log(b.length + 1);
  if (denominator == 0) return 0;
  return intersection / denominator;
}

double _positionWeight(SummarySentence sentence, SummaryOptions options) {
  var weight = 1.0;
  if (sentence.isFirstParagraph && sentence.isParagraphStart) {
    weight *= options.weightFirstSentence;
  } else if (sentence.isFirstParagraph) {
    weight *= options.weightFirstParagraph;
  }
  if (!sentence.isFirstParagraph && sentence.isParagraphStart) {
    weight *= options.weightParagraphStart;
  }
  if (sentence.isParagraphEnd) {
    weight *= options.weightParagraphEnd;
  }
  return weight;
}

/// TextRank 迭代，结果写回 `sentence.score`。
void textRank(
  List<SummarySentence> sentences,
  List<Set<String>> ngramSets,
  SummaryOptions options, {
  Set<String>? keywords,
}) {
  final n = sentences.length;
  if (n == 0) return;
  if (n == 1) {
    var score = _positionWeight(sentences[0], options);
    if (keywords != null && options.keywordWeight > 0) {
      score *= _keywordWeightForSentence(
        sentences[0],
        keywords,
        options.keywordWeight,
      );
    }
    sentences[0].score = score;
    return;
  }

  final simMatrix = List.generate(n, (_) => List<double>.filled(n, 0));
  final simSums = List<double>.filled(n, 0);

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final sim = similarity(ngramSets[i], ngramSets[j]);
      simMatrix[i][j] = sim;
      simMatrix[j][i] = sim;
      simSums[i] += sim;
      simSums[j] += sim;
    }
  }

  final initScores = <double>[];
  for (final sentence in sentences) {
    var score = _positionWeight(sentence, options);
    if (keywords != null && options.keywordWeight > 0) {
      score *= _keywordWeightForSentence(
        sentence,
        keywords,
        options.keywordWeight,
      );
    }
    initScores.add(score);
  }
  final scores = List<double>.from(initScores);

  for (var iteration = 0; iteration < options.maxIterations; iteration++) {
    final nextScores = List<double>.filled(n, 0);
    var maxDiff = 0.0;

    for (var i = 0; i < n; i++) {
      var rankSum = 0.0;
      for (var j = 0; j < n; j++) {
        if (i == j || simSums[j] == 0) continue;
        rankSum += (simMatrix[i][j] / simSums[j]) * scores[j];
      }
      nextScores[i] =
          (1 - options.dampingFactor) * initScores[i] +
          options.dampingFactor * rankSum;
      final diff = (nextScores[i] - scores[i]).abs();
      if (diff > maxDiff) maxDiff = diff;
    }

    for (var i = 0; i < n; i++) {
      scores[i] = nextScores[i];
    }

    if (maxDiff < options.convergenceThreshold) break;
  }

  for (var i = 0; i < n; i++) {
    sentences[i].score = scores[i];
  }
}

/// 级别 → 句数（与上游 sentenceCountForLevel 一致）。
int sentenceCountForLevel(int totalSentences, int level) {
  if (level >= 5) return totalSentences;
  if (level == 4) return math.max(3, (totalSentences * 0.5).ceil());
  if (level == 3) return math.max(3, (totalSentences * 0.3).ceil());
  if (level == 2) return math.max(2, (totalSentences * 0.2).ceil());
  return 1;
}

/// MMR 多样性选句。
List<SummarySentence> selectByMmr(
  List<SummarySentence> sentences,
  List<Set<String>> ngramSets,
  int targetCount,
  double lambda,
) {
  if (sentences.length <= targetCount) return List.of(sentences);

  final scores = sentences.map((sentence) => sentence.score).toList();
  final maxScore = scores.reduce(math.max);
  final minScore = scores.reduce(math.min);
  final range = (maxScore - minScore) == 0 ? 1.0 : maxScore - minScore;
  final normalized = scores
      .map((score) => (score - minScore) / range)
      .toList(growable: false);

  final selected = <int>[];
  final remaining = <int>{for (var i = 0; i < sentences.length; i++) i};

  var bestIndex = -1;
  var bestScore = double.negativeInfinity;
  for (var i = 0; i < sentences.length; i++) {
    if (normalized[i] > bestScore) {
      bestScore = normalized[i];
      bestIndex = i;
    }
  }
  selected.add(bestIndex);
  remaining.remove(bestIndex);

  while (selected.length < targetCount && remaining.isNotEmpty) {
    var bestMmr = double.negativeInfinity;
    var bestCandidate = -1;

    for (final index in remaining) {
      final relevance = lambda * normalized[index];
      var maxSim = 0.0;
      for (final selectedIndex in selected) {
        final sim = similarity(ngramSets[index], ngramSets[selectedIndex]);
        if (sim > maxSim) maxSim = sim;
      }
      final mmr = relevance - (1 - lambda) * maxSim;
      if (mmr > bestMmr) {
        bestMmr = mmr;
        bestCandidate = index;
      }
    }

    if (bestCandidate == -1) break;
    selected.add(bestCandidate);
    remaining.remove(bestCandidate);
  }

  final picked = selected.map((index) => sentences[index]).toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  return picked;
}

/// 主入口：抽取式摘要。
///
/// 传 [sentenceCountOverride] 时按句数取（用于"章节梗概控制在 N 句"），
/// 否则按 [SummaryOptions.compressionLevel] 映射。
SummaryResult extractSummary(
  String text, {
  SummaryOptions options = const SummaryOptions(),
  int? sentenceCountOverride,
}) {
  final sentences = splitSentences(
    text,
    minSentenceLength: options.minSentenceLength,
  );
  if (sentences.isEmpty) {
    return SummaryResult(
      summary: const <SummarySentence>[],
      sentences: const <SummarySentence>[],
      text: '',
      compressionLevel: options.compressionLevel,
    );
  }

  final ngramSets = <Set<String>>[];
  for (final sentence in sentences) {
    ngramSets.add(extractNgrams(sentence.text, options.ngramSize));
  }

  final keywords = extractKeywords(sentences, 20);
  textRank(sentences, ngramSets, options, keywords: keywords);

  final target = sentenceCountOverride ??
      sentenceCountForLevel(sentences.length, options.compressionLevel);
  final picked = selectByMmr(sentences, ngramSets, target, options.mmrLambda);

  return SummaryResult(
    summary: picked,
    sentences: sentences,
    text: picked.map((sentence) => sentence.text).join(' '),
    compressionLevel: options.compressionLevel,
  );
}

/// 子句切分（上游 level 1 使用；这里保留给"章末钩子"取主干句）。
List<String> splitClauses(String sentence, {int minLength = 3}) {
  if (sentence.isEmpty) return const <String>[];
  final clauses = <String>[];
  final units = sentence.codeUnits;
  var current = StringBuffer();

  for (var i = 0; i < units.length; i++) {
    final char = String.fromCharCode(units[i]);
    current.write(char);
    if (_clauseSeparators.contains(char)) {
      final trimmed = current.toString().trim();
      if (trimmed.length >= minLength) clauses.add(trimmed);
      current = StringBuffer();
    }
  }

  final rest = current.toString().trim();
  if (rest.length >= minLength) clauses.add(rest);
  return clauses;
}
