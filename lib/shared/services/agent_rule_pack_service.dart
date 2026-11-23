// 职责: 读取内置规则包资源，并把选中的规则包写入作品内容库。
// 关联文件:
//   assets/rule_packs/rule_packs.json
//   lib/shared/models/agent_rule_pack.dart
//   lib/shared/services/agent_rule_copy_service.dart
//   lib/desktop/widgets/agent_management/agent_rule_pack_dialog.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../database/novel_content_database.dart';
import '../logger/app_logger.dart';
import '../models/agent_rule_pack.dart';
import '../utils/random_id.dart';
import 'agent_rule_copy_service.dart';
import 'novel_content.dart';

final _log = AppLogger.forModule('AgentRulePack');

const String _assetPath = 'assets/rule_packs/rule_packs.json';

List<AgentRulePack>? _cache;

/// 读取内置规则包（assets/rule_packs/rule_packs.json），进程内缓存一次。
Future<List<AgentRulePack>> loadAgentRulePacks({bool refresh = false}) async {
  final cached = _cache;
  if (cached != null && !refresh) {
    return cached;
  }
  try {
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('rule_packs.json 顶层不是对象');
    }
    final packs = <AgentRulePack>[
      for (final item in (decoded['packs'] as List? ?? const []))
        if (item is Map<String, dynamic>) AgentRulePack.fromJson(item),
    ].where((pack) {
      return pack.id.isNotEmpty && pack.name.isNotEmpty && pack.rules.isNotEmpty;
    }).toList(growable: false);
    _cache = packs;
    return packs;
  } catch (error, stackTrace) {
    _log.error('load rule packs failed asset=$_assetPath', error: error, stackTrace: stackTrace);
    return const <AgentRulePack>[];
  }
}

/// 把规则包中的规则写入目标作品，跳过目标里已有的同名规则。
///
/// 走 [copyAgentRulesToNovel] 的同一条路径：重新生成 ID、追加排序、按名称去重。
/// 返回实际写入的条数。
Future<int> importAgentRulePack({
  required NovelContentService targetService,
  required List<AgentRule> currentRules,
  required AgentRulePack pack,
  required String targetPath,
}) async {
  final now = DateTime.now();
  final sourceRules = <AgentRule>[
    for (final rule in pack.rules)
      AgentRule(
        id: buildRandomId('pack_rule'),
        name: rule.name,
        content: rule.content,
        enabled: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
        deletedAt: notDeletedSentinel,
      ),
  ];
  return copyAgentRulesToNovel(
    targetService: targetService,
    currentRules: currentRules,
    sourceRules: sourceRules,
    sourcePath: 'asset:$_assetPath#${pack.id}',
    targetPath: targetPath,
  );
}
