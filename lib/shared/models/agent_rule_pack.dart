// 职责: 内置智能体规则包的数据模型（题材包 → 若干条规则）。
// 关联文件:
//   assets/rule_packs/rule_packs.json
//   lib/shared/services/agent_rule_pack_service.dart
//   lib/desktop/widgets/agent_management/agent_rule_pack_dialog.dart
/// 规则包中的一条规则（名称 + 约束正文），导入时转成作品内的 [AgentRule]。
class AgentRulePackRule {
  const AgentRulePackRule({required this.name, required this.content});

  factory AgentRulePackRule.fromJson(Map<String, dynamic> json) {
    return AgentRulePackRule(
      name: (json['name'] as String? ?? '').trim(),
      content: (json['content'] as String? ?? '').trim(),
    );
  }

  final String name;
  final String content;
}

/// 一个题材规则包：名称、一句话摘要、分类与规则列表。
class AgentRulePack {
  const AgentRulePack({
    required this.id,
    required this.name,
    required this.summary,
    required this.category,
    required this.rules,
  });

  factory AgentRulePack.fromJson(Map<String, dynamic> json) {
    final rawRules = (json['rules'] as List? ?? const []);
    return AgentRulePack(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      summary: (json['summary'] as String? ?? '').trim(),
      category: (json['category'] as String? ?? '').trim(),
      rules: [
        for (final item in rawRules)
          if (item is Map<String, dynamic>) AgentRulePackRule.fromJson(item),
      ],
    );
  }

  final String id;
  final String name;
  final String summary;
  final String category;
  final List<AgentRulePackRule> rules;

  /// 供搜索匹配：名称、摘要与分类任意命中即可。
  bool matchesQuery(String query) {
    if (query.isEmpty) {
      return true;
    }
    final q = query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        summary.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q);
  }
}
