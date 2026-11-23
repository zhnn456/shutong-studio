// 职责: 验证规则包导入链路 — 写入作品库、按名称去重、排序连续。
// 关联文件:
//   lib/shared/services/agent_rule_pack_service.dart
//   lib/shared/services/novel_content.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/agent_rule_pack_service.dart';
import 'package:reveric/shared/services/novel_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('导入规则包：写入、去重、排序连续', () async {
    final dir = await Directory.systemTemp.createTemp('rule_pack_');
    final db = NovelContentDatabase(p.join(dir.path, 'novel.sqlite'));
    final service = NovelContentService(db);
    final packs = await loadAgentRulePacks(refresh: true);
    final pack = packs.firstWhere((item) => item.id == 'island_survival_system');

    final imported = await importAgentRulePack(
      targetService: service,
      currentRules: const <AgentRule>[],
      pack: pack,
      targetPath: db.filePath,
    );
    expect(imported, pack.rules.length);

    final rules = await service.getAgentRules();
    expect(rules.length, pack.rules.length);
    expect(
      {for (final rule in rules) rule.name},
      {for (final rule in pack.rules) rule.name},
    );
    for (final rule in rules) {
      expect(rule.enabled, isTrue);
      expect(rule.content.trim(), isNotEmpty);
    }
    final orders = [for (final rule in rules) rule.sortOrder]..sort();
    expect(orders, [for (var i = 0; i < rules.length; i++) i]);

    // 二次导入同名规则应全部跳过。
    final again = await importAgentRulePack(
      targetService: service,
      currentRules: rules,
      pack: pack,
      targetPath: db.filePath,
    );
    expect(again, 0);
    expect((await service.getAgentRules()).length, pack.rules.length);

    await db.close();
    await dir.delete(recursive: true);
  });
}
