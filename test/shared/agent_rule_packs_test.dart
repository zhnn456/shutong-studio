// 职责: 校验内置规则包资源可被加载、结构完整（ID/名称唯一、规则非空）。
// 关联文件:
//   assets/rule_packs/rule_packs.json
//   lib/shared/services/agent_rule_pack_service.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/agent_rule_pack_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内置规则包可加载且结构完整', () async {
    final packs = await loadAgentRulePacks(refresh: true);

    expect(packs, isNotEmpty, reason: 'assets/rule_packs/rule_packs.json 应可被读取');
    expect(packs.length, greaterThanOrEqualTo(8), reason: '题材包数量不应被意外删减');

    final ids = <String>{};
    final names = <String>{};
    for (final pack in packs) {
      expect(pack.id, isNotEmpty);
      expect(pack.name, isNotEmpty);
      expect(pack.rules, isNotEmpty, reason: '${pack.name} 应至少有一条规则');
      expect(ids.add(pack.id), isTrue, reason: '规则包 ID 重复: ${pack.id}');
      expect(names.add(pack.name), isTrue, reason: '规则包名称重复: ${pack.name}');

      final ruleNames = <String>{};
      for (final rule in pack.rules) {
        expect(rule.name, isNotEmpty);
        expect(rule.content, isNotEmpty);
        expect(
          ruleNames.add(rule.name),
          isTrue,
          reason: '${pack.name} 内规则名重复: ${rule.name}',
        );
      }
    }
  });
}
