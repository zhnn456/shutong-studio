// 职责: 小说编辑器内智能体规则页 — 左题材体系、中规则列表、右常驻详情，替代平铺卡片网格。
// 关联文件:
//   lib/desktop/widgets/agent_management/agent_rule_library_page.dart
//   lib/desktop/widgets/agent_management/home_management_cards.dart
//   lib/desktop/widgets/agent_management/agent_rule_edit_panel.dart
//   lib/desktop/widgets/agent_management/agent_rule_copy_dialog.dart
//   lib/shared/components/reveric_context_menu.dart
//   lib/shared/components/reveric_search_field.dart
//   lib/shared/components/reveric_switch.dart
//   lib/shared/models/agent_rule_pack.dart
//   lib/shared/models/novel_workspace.dart
//   lib/shared/providers/agent_rule_providers.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_rule.json
//   assets/translations/zh-CN/agent_rule.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/hooks.md
//   .agents/rules/search-debounce.md

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_search_field.dart';
import '../../../shared/components/reveric_switch.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/models/agent_rule_pack.dart';
import '../../../shared/models/novel_workspace.dart';
import '../../../shared/providers/agent_rule_providers.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/services/agent_rule_pack_service.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import 'agent_rule_copy_dialog.dart';
import 'agent_rule_library_page.dart';
import 'home_management_cards.dart';

final _log = AppLogger.forModule('AgentRulesGrid');

const _ungroupedLabel = '未分组';

bool _matchesAgentRule(String query, AgentRule rule) {
  if (query.isEmpty) {
    return true;
  }
  final q = query.toLowerCase();
  return rule.name.toLowerCase().contains(q) ||
      rule.content.toLowerCase().contains(q);
}

/// 规则名 → 规则包分类（题材）的索引，用于左栏体系分组；同名规则以先出现的包为准。
Map<String, String> _ruleGroupIndex(List<AgentRulePack> packs) {
  final index = <String, String>{};
  for (final pack in packs) {
    final group = pack.category.trim().isEmpty ? '其他' : pack.category.trim();
    for (final rule in pack.rules) {
      index.putIfAbsent(rule.name, () => group);
    }
  }
  return index;
}

class AgentRulesGridPage extends HookConsumerWidget {
  const AgentRulesGridPage({
    super.key,
    required this.databasePath,
    required this.novelId,
    required this.headerGestureExclusionKey,
    required this.onOpen,
    required this.onCreate,
    this.onBack,
  });

  final String databasePath;
  final String novelId;
  final GlobalKey headerGestureExclusionKey;
  final ValueChanged<AgentRule> onOpen;
  final VoidCallback onCreate;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final rulesAsync = ref.watch(agentRulesStreamProvider(databasePath));
    final search = useDebouncedSearch();
    final group = useState<String?>(null);
    final selectedId = useState<String?>(null);
    final packsAsync = useFuture(
      useMemoized(() => loadAgentRulePacks(), const []),
    );
    final groupIndex = _ruleGroupIndex(packsAsync.data ?? const []);

    Future<void> copyFromOtherNovel() async {
      final copied = await showAgentRuleCopyDialog(
        context: context,
        databasePath: databasePath,
        novelId: novelId,
      );
      if (copied == null || copied == 0 || !context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t(
              LocaleKeys.agentRuleCopySuccess,
              namedArgs: {'count': '$copied'},
            ),
          ),
        ),
      );
    }

    Future<void> importFromLibrary() async {
      final imported = await showAgentRuleLibraryPage(
        context: context,
        databasePath: databasePath,
        novelId: novelId,
      );
      if (imported == null || imported == 0 || !context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t(
              LocaleKeys.agentRulePackImported,
              namedArgs: {'count': '$imported'},
            ),
          ),
        ),
      );
    }

    Future<void> setEnabled(AgentRule rule, bool enabled) async {
      try {
        await ref
            .read(novelContentServiceProvider(databasePath))
            .upsertAgentRule(
              rule.copyWith(enabled: enabled, updatedAt: DateTime.now()),
            );
      } catch (error, stackTrace) {
        _log.error(
          'toggle agent rule enabled failed id=${rule.id} enabled=$enabled',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
          );
        }
      }
    }

    Future<void> deleteRule(AgentRule rule) async {
      final confirmed = await showConfirmDialog(
        context,
        title: context.t(LocaleKeys.commonDelete),
        message: context.t(
          LocaleKeys.agentRuleDeleteConfirm,
          namedArgs: {'name': rule.name},
        ),
        confirmLabel: context.t(LocaleKeys.commonDelete),
        variant: ConfirmDialogVariant.error,
      );
      if (!confirmed || !context.mounted) {
        return;
      }
      try {
        await ref
            .read(novelContentServiceProvider(databasePath))
            .deleteAgentRule(rule.id);
        selectedId.value = null;
      } catch (error, stackTrace) {
        _log.error(
          'delete agent rule failed id=${rule.id}',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.commonDeleteFailed))),
          );
        }
      }
    }

    return HomeManagementScaffold(
      headerGestureExclusionKey: headerGestureExclusionKey,
      icon: RevericIcons.rule_outlined,
      titleKey: LocaleKeys.agentRuleTitle,
      createLabelKey: LocaleKeys.commonCreate,
      onCreate: onCreate,
      onBack: onBack,
      secondaryAction: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: () => unawaited(importFromLibrary()),
            icon: const RevericIcon(RevericIcons.rule_outlined, size: 16),
            label: Text(context.t(LocaleKeys.agentRulePackLibrary)),
          ),
          const SizedBox(width: RevericSpacing.xs),
          TextButton.icon(
            onPressed: () => unawaited(copyFromOtherNovel()),
            icon: const RevericIcon(RevericIcons.copy, size: 16),
            label: Text(context.t(LocaleKeys.agentRuleCopyFromNovel)),
          ),
        ],
      ),
      child: rulesAsync.when(
        loading: () => const HomeManagementLoadingState(),
        error: (_, _) => HomeManagementErrorState(
          message: context.t(LocaleKeys.commonLoadFailed),
        ),
        data: (rules) {
          final groups = <String, List<AgentRule>>{};
          for (final rule in rules) {
            final key = groupIndex[rule.name] ?? _ungroupedLabel;
            (groups[key] ??= <AgentRule>[]).add(rule);
          }
          final groupNames = groups.keys.toList(growable: false);
          final activeGroup = group.value;
          final visible = rules
              .where(
                (rule) => !search.active
                    ? activeGroup == null ||
                          (groupIndex[rule.name] ?? _ungroupedLabel) ==
                              activeGroup
                    : _matchesAgentRule(search.query, rule),
              )
              .toList(growable: false);
          final selected = rules
              .where((rule) => rule.id == selectedId.value)
              .firstOrNull;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 232,
                child: _RuleGroupColumn(
                  total: rules.length,
                  groups: groups,
                  order: groupNames,
                  selected: activeGroup,
                  onSelect: (value) {
                    group.value = value;
                    search.controller.clear();
                  },
                ),
              ),
              _VerticalRule(color: colors.border),
              SizedBox(
                width: 392,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    RevericSpacing.lg,
                    RevericSpacing.x2l,
                    RevericSpacing.lg,
                    RevericSpacing.x2l,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            activeGroup ?? context.t(LocaleKeys.agentRuleTitle),
                            style: typo.uiTinySemibold.copyWith(
                              color: colors.textSubtle,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${visible.length}',
                            style: typo.uiTiny.copyWith(
                              color: colors.textSubtle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: RevericSpacing.sm),
                      RevericSearchField(
                        controller: search.controller,
                        hint: context.t(LocaleKeys.commonSearch),
                        height: 34,
                      ),
                      const SizedBox(height: RevericSpacing.sm),
                      Expanded(
                        child: visible.isEmpty
                            ? Center(
                                child: Text(
                                  context.t(LocaleKeys.agentRuleEmpty),
                                  style: typo.uiSmall.copyWith(
                                    color: colors.textMuted,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: visible.length,
                                itemBuilder: (context, index) {
                                  final rule = visible[index];
                                  return _RuleRow(
                                    rule: rule,
                                    active: rule.id == selectedId.value,
                                    onTap: () => selectedId.value = rule.id,
                                    onToggle: (enabled) =>
                                        unawaited(setEnabled(rule, enabled)),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: RevericSpacing.xs),
                      _FootHint(
                        label: context.t(LocaleKeys.agentRuleNextChatHint),
                      ),
                    ],
                  ),
                ),
              ),
              _VerticalRule(color: colors.border),
              Expanded(
                child: _RuleDetailColumn(
                  rule: selected,
                  groupLabel: selected == null
                      ? null
                      : (groupIndex[selected.name] ?? _ungroupedLabel),
                  onEdit: selected == null ? null : () => onOpen(selected),
                  onDelete: selected == null
                      ? null
                      : () => unawaited(deleteRule(selected)),
                  onToggle: selected == null
                      ? null
                      : (enabled) => unawaited(setEnabled(selected, enabled)),
                  onCreate: onCreate,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VerticalRule extends StatelessWidget {
  const _VerticalRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: RevericSizes.dividerThickness, color: color);
  }
}

class _FootHint extends StatelessWidget {
  const _FootHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Text(
      label,
      style: RevericTheme.typographyOf(
        context,
      ).uiTiny.copyWith(color: colors.textSubtle, height: 1.4),
    );
  }
}

class _RuleGroupColumn extends StatelessWidget {
  const _RuleGroupColumn({
    required this.total,
    required this.groups,
    required this.order,
    required this.selected,
    required this.onSelect,
  });

  final int total;
  final Map<String, List<AgentRule>> groups;
  final List<String> order;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x2l,
        RevericSpacing.x2l,
        RevericSpacing.lg,
        RevericSpacing.x2l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t(LocaleKeys.agentRuleGroupTitle),
            style: typo.uiTinySemibold.copyWith(color: colors.textSubtle),
          ),
          const SizedBox(height: RevericSpacing.xs),
          _GroupRow(
            label: context.t(LocaleKeys.agentRulePackCategoryAll),
            count: total,
            active: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final name in order)
            _GroupRow(
              label: name,
              count: groups[name]?.length ?? 0,
              active: selected == name,
              onTap: () => onSelect(name),
            ),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xxs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        hoverColor: colors.hover,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: active ? colors.surfaceContainerHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(RevericRadius.medium),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: (active ? typo.uiSmallSemibold : typo.uiSmall)
                      .copyWith(
                        color: active
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$count',
                style: typo.uiTiny.copyWith(color: colors.textSubtle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.active,
    required this.onTap,
    required this.onToggle,
  });

  final AgentRule rule;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final reference = AiContextReference(
      kind: AiContextReferenceKind.agent_rule,
      section: NovelWorkspaceSection.overview,
      itemId: rule.id,
      label: rule.name,
    );

    final row = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      hoverColor: colors.hover,
      child: Container(
        padding: const EdgeInsets.all(RevericSpacing.md),
        decoration: BoxDecoration(
          color: active ? colors.surfaceContainerHigh : colors.surface,
          border: Border.all(
            color: active ? colors.accent : colors.borderInput,
          ),
          borderRadius: BorderRadius.circular(RevericRadius.medium),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          rule.name,
                          style: typo.uiSmallSemibold.copyWith(
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: RevericSpacing.sm),
                      if (!rule.enabled)
                        Text(
                          context.t(LocaleKeys.agentRuleDisabled),
                          style: typo.uiTiny.copyWith(color: colors.textSubtle),
                        ),
                    ],
                  ),
                  const SizedBox(height: RevericSpacing.xxs),
                  Text(
                    rule.content,
                    style: typo.uiTiny.copyWith(
                      color: colors.textMuted,
                      height: 1.45,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: RevericSpacing.sm),
            RevericSwitch(
              value: rule.enabled,
              onChanged: (enabled) => onToggle(enabled),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
      child: Draggable<AiContextReference>(
        data: reference,
        feedback: _RuleDragFeedback(rule: rule),
        childWhenDragging: Opacity(opacity: 0.55, child: row),
        child: row,
      ),
    );
  }
}

class _RuleDragFeedback extends StatelessWidget {
  const _RuleDragFeedback({required this.rule});

  final AgentRule rule;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.lg,
          vertical: RevericSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(RevericRadius.pill),
          border: Border.all(color: colors.accent),
          boxShadow: [
            BoxShadow(
              color: colors.textPrimary.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(
              RevericIcons.rule_outlined,
              size: 14,
              color: colors.accent,
            ),
            const SizedBox(width: RevericSpacing.xs),
            Text(
              rule.name,
              style: typo.uiSmall.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleDetailColumn extends StatelessWidget {
  const _RuleDetailColumn({
    required this.rule,
    required this.groupLabel,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onCreate,
  });

  final AgentRule? rule;
  final String? groupLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggle;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final current = rule;

    if (current == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t(LocaleKeys.agentRuleOverviewHint),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: RevericSpacing.md),
            RevericButton.secondary(
              label: context.t(LocaleKeys.commonCreate),
              icon: RevericIcons.add,
              size: RevericButtonSize.compact,
              onPressed: onCreate,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.x2l,
            vertical: RevericSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            border: Border(
              bottom: BorderSide(
                color: colors.border,
                width: RevericSizes.dividerThickness,
              ),
            ),
          ),
          child: Row(
            children: [
              if (groupLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.sm,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border.all(color: colors.borderInput),
                    borderRadius: BorderRadius.circular(RevericRadius.small),
                  ),
                  child: Text(
                    groupLabel!,
                    style: typo.uiTiny.copyWith(color: colors.textSecondary),
                  ),
                ),
              const Spacer(),
              Text(
                context.t(
                  current.enabled
                      ? LocaleKeys.agentRuleEnabled
                      : LocaleKeys.agentRuleDisabled,
                ),
                style: typo.uiTiny.copyWith(
                  color: current.enabled ? colors.accent : colors.textSubtle,
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              RevericSwitch(
                value: current.enabled,
                onChanged: (enabled) => onToggle?.call(enabled),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.x2l,
              RevericSpacing.x2l,
              RevericSpacing.x2l,
              RevericSpacing.x2l,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.name,
                  style: typo.heading2.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: RevericSpacing.xs),
                Text(
                  context.t(LocaleKeys.agentRuleContent),
                  style: typo.uiTinySemibold.copyWith(color: colors.textSubtle),
                ),
                const SizedBox(height: RevericSpacing.xs),
                Text(
                  current.content,
                  style: typo.uiSmall.copyWith(
                    color: colors.textSecondary,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: RevericSpacing.lg),
                Text(
                  context.t(LocaleKeys.agentRuleNextChatHint),
                  style: typo.uiTiny.copyWith(
                    color: colors.textSubtle,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.x2l,
            RevericSpacing.md,
            RevericSpacing.x2l,
            RevericSpacing.x2l,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: colors.border,
                width: RevericSizes.dividerThickness,
              ),
            ),
          ),
          child: Row(
            children: [
              RevericButton.secondary(
                label: context.t(LocaleKeys.commonEdit),
                icon: RevericIcons.edit_outlined,
                size: RevericButtonSize.compact,
                onPressed: onEdit,
              ),
              const SizedBox(width: RevericSpacing.md),
              RevericButton.danger(
                label: context.t(LocaleKeys.commonDelete),
                icon: RevericIcons.delete_outline,
                size: RevericButtonSize.compact,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 供外部创建「新建规则」草稿，与旧空态 / 中栏 + 行为一致。
AgentRule newAgentRuleDraft() {
  final now = DateTime.now();
  return AgentRule(
    id: '__new__${now.microsecondsSinceEpoch}',
    name: '',
    content: '',
    enabled: true,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
    deletedAt: notDeletedSentinel,
  );
}
