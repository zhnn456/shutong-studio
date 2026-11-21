// 职责: 「沉淀清单」是否已出过 — 决定章节头部按钮是「沉淀本章」还是「确认入库」。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart（出清单时写标记、入库后清标记）
//   lib/desktop/widgets/workspace/chapter_editor.dart（按状态切按钮文案）
//
// 为什么用 AppStates 存标记：
//   这是一次性的"流程状态"，不是书的正式数据；放 AppStates 既不动表结构，
//   也不会污染章节表。key 带章节 id，换书不串味。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/novel_providers.dart';

const String settleListedKeyPrefix = 'settle_listed_';

String settleListedKey(String chapterId) => '$settleListedKeyPrefix$chapterId';

/// 是否已经为这一章出过沉淀清单（出过就等作者确认入库）。
final settleListedProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, chapterId) async {
    final database = ref.watch(appDatabaseProvider);
    final value = await database.appStateDao.get(settleListedKey(chapterId));
    return value != null && value.isNotEmpty;
  },
);
