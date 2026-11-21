// 职责: 全书创作目标的读取入口 — 用 plain Riverpod 的 FutureProvider，避免新增 codegen。
// 关联文件:
//   lib/shared/services/novel_goal.dart
//   lib/shared/providers/novel_providers.dart（appDatabaseProvider）
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart（消费方）
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/novel_goal.dart';
import 'novel_providers.dart';

/// 读取某本小说的目标；未设置时返回 null（界面给"设定目标"入口）。
final novelGoalProvider = FutureProvider.autoDispose.family<NovelGoal?, String>(
  (ref, novelId) async {
    final database = ref.watch(appDatabaseProvider);
    return readNovelGoal(database, novelId);
  },
);
