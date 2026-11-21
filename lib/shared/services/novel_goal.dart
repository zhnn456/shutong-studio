// 职责: 全书的创作目标（目标章数 / 目标总字数），供大纲、章纲、写章与进度卡共用同一份约束。
// 关联文件:
//   lib/shared/database/daos/app_state_dao.dart（AppStates KV 存储，key = novel_goal_<novelId>）
//   lib/shared/providers/novel_goal_provider.dart
//   lib/desktop/widgets/workspace/novel_overview.dart（进度卡展示与编辑入口）
//   lib/shared/services/chapter_briefing_context.dart（写章上下文里带上目标，让模型知道该写多长）
//
// 为什么单独存一份：
//   没有目标时，AI 只能按"这一章写多少"自由发挥，全书节奏无从控制；
//   v2 复验里"第一章 2696 字、第二十行还在铺垫"就是没有总量约束的结果。
//   目标落在 AppStates（key/value）而不是 novels 表，避免为两个数字改表结构、动迁移。
import 'dart:convert';

import '../database/app_database.dart';

const String novelGoalKeyPrefix = 'novel_goal_';

/// 默认目标：网文常见的 100 章 / 3000 字每章。
const int defaultTargetChapters = 100;
const int defaultWordsPerChapter = 3000;

class NovelGoal {
  const NovelGoal({required this.chapters, required this.wordsPerChapter});

  /// 目标章数。
  final int chapters;

  /// 目标每章字数（目标总字数由两者相乘得到）。
  final int wordsPerChapter;

  int get totalWords => chapters * wordsPerChapter;

  bool get isUsable => chapters > 0 && wordsPerChapter > 0;

  NovelGoal copyWith({int? chapters, int? wordsPerChapter}) => NovelGoal(
    chapters: chapters ?? this.chapters,
    wordsPerChapter: wordsPerChapter ?? this.wordsPerChapter,
  );

  Map<String, dynamic> toJson() => {
    'chapters': chapters,
    'words_per_chapter': wordsPerChapter,
  };

  static NovelGoal? fromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final chapters = decoded['chapters'];
      final words = decoded['words_per_chapter'];
      if (chapters is! num || words is! num) return null;
      final goal = NovelGoal(
        chapters: chapters.toInt(),
        wordsPerChapter: words.toInt(),
      );
      return goal.isUsable ? goal : null;
    } catch (_) {
      return null;
    }
  }
}

String novelGoalStorageKey(String novelId) => '$novelGoalKeyPrefix$novelId';

Future<NovelGoal?> readNovelGoal(
  AppDatabase database,
  String novelId,
) async {
  final raw = await database.appStateDao.get(novelGoalStorageKey(novelId));
  if (raw == null || raw.trim().isEmpty) return null;
  return NovelGoal.fromJson(raw);
}

Future<void> writeNovelGoal(
  AppDatabase database,
  String novelId,
  NovelGoal goal,
) async {
  await database.appStateDao.set(
    key: novelGoalStorageKey(novelId),
    value: jsonEncode(goal.toJson()),
  );
}

/// 写进模型上下文的一行目标说明。没有目标时返回空串，不写无意义的占位。
String novelGoalPromptLine(NovelGoal? goal) {
  if (goal == null || !goal.isUsable) return '';
  return '全书目标：共 ${goal.chapters} 章，每章约 ${goal.wordsPerChapter} 字（合计约 ${_formatWan(goal.totalWords)}）。'
      '章纲与正文都要按这个节奏分配，不要一章写掉整卷的进度。';
}

String _formatWan(int words) {
  final wan = words / 10000;
  final text = wan >= 10 ? wan.toStringAsFixed(0) : wan.toStringAsFixed(1);
  return '$text 万字';
}
