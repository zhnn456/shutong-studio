// 职责: 文风 DNA — 作者贴 1-5 段自己的样文，软件算出可量化的文风特征并常驻注入写章上下文。
// 关联文件:
//   lib/shared/services/chapter_briefing_context.dart（写章/章纲上下文里注入这段特征）
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart（概览上的「文风」入口）
//
// 为什么用代码算而不是让模型"感受"：
//   让模型自己总结文风，总结出来的永远是"细腻、有张力"这类空话，落不到句子上。
//   这里直接数：平均句长、段落长度、对白占比、高频连接词、AI 味套话出现次数——
//   这些数字模型看得懂，也照着写得出。
import '../database/app_database.dart';

const String novelStyleKeyPrefix = 'novel_style_';

String novelStyleStorageKey(String novelId) => '$novelStyleKeyPrefix$novelId';

/// 样文上限：太多会挤掉写章上下文里真正重要的设定。
const int styleSampleMaxCharacters = 2000;

/// 常见的"AI 味"套话，出现频率高说明腔调不是人写的。
const List<String> _aiFlavorPhrases = [
  '不禁',
  '仿佛',
  '似乎',
  '这一刻',
  '心中涌起',
  '一股暖流',
  '深吸一口气',
  '嘴角勾起',
  '意味深长',
  '空气仿佛凝固',
];

Future<String?> readNovelStyle(AppDatabase database, String novelId) async {
  final raw = await database.appStateDao.get(novelStyleStorageKey(novelId));
  if (raw == null || raw.trim().isEmpty) return null;
  return raw;
}

Future<void> writeNovelStyle(
  AppDatabase database,
  String novelId,
  String sample,
) async {
  await database.appStateDao.set(
    key: novelStyleStorageKey(novelId),
    value: sample.trim(),
  );
}

/// 把样文压成一段可注入的文风描述。没有样文时返回空串。
String novelStylePromptSection(String? sample) {
  final text = (sample ?? '').trim();
  if (text.isEmpty) return '';
  final clipped = text.length > styleSampleMaxCharacters
      ? text.substring(0, styleSampleMaxCharacters)
      : text;
  final stats = _computeStyleStats(clipped);
  return '## 文风（照这个腔调写，不要换成别的语气）\n'
      '${stats.join('；')}\n'
      '样文节选：\n$clipped';
}

List<String> _computeStyleStats(String text) {
  final stats = <String>[];
  final sentences = text
      .split(RegExp(r'[。！？…]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
  if (sentences.isNotEmpty) {
    final total = sentences.fold<int>(0, (sum, item) => sum + item.length);
    final avg = total / sentences.length;
    final longest = sentences.reduce(
      (a, b) => a.length >= b.length ? a : b,
    ).length;
    stats.add('平均句长 ${avg.toStringAsFixed(1)} 字（最长 $longest 字）');
  }

  final paragraphs = text
      .split(RegExp(r'\n+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
  if (paragraphs.isNotEmpty) {
    final total = paragraphs.fold<int>(0, (sum, item) => sum + item.length);
    stats.add('平均段长 ${(total / paragraphs.length).toStringAsFixed(0)} 字');
    stats.add('共 ${paragraphs.length} 段');
  }

  final dialogueMarks = RegExp(r'[「“"]').allMatches(text).length;
  if (text.isNotEmpty) {
    final ratio = dialogueMarks * 100 / text.length;
    stats.add('对白标记密度 ${ratio.toStringAsFixed(1)}%');
  }

  final flavor = <String>[];
  for (final phrase in _aiFlavorPhrases) {
    final count = phrase.allMatches(text).length;
    if (count > 0) flavor.add('$phrase×$count');
  }
  stats.add(
    flavor.isEmpty ? '未出现常见 AI 味套话' : '注意避免复现这些高频词：${flavor.join('、')}',
  );
  return stats;
}
