// 职责: 从内置规则库导入智能体规则 — 左栏选题材包，右栏勾选规则并写入当前作品。
// 关联文件:
//   assets/rule_packs/rule_packs.json
//   lib/shared/models/agent_rule_pack.dart
//   lib/shared/services/agent_rule_pack_service.dart
//   lib/shared/services/agent_rule_copy_service.dart
//   lib/desktop/widgets/agent_management/agent_rules_grid_page.dart
//   lib/shared/providers/agent_rule_providers.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_rule.json
//   assets/translations/zh-CN/agent_rule.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/hooks.md
//   .agents/rules/i18n.md
//   .agents/rules/search-debounce.md
//   .agents/rules/error-handling.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/dialog_feedback.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_search_field.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/models/agent_rule_pack.dart';
import '../../../shared/providers/agent_rule_providers.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/services/agent_rule_pack_service.dart';
import '../../../shared/theme/theme.dart';

final _log = AppLogger.forModule('AgentRulePackDialog');

/// 打开「规则库」导入对话框；返回实际导入条数，取消时返回 null。
Future<int?> showAgentRulePackDialog({
  required BuildContext context,
  required String databasePath,
  required String novelId,
}) {
  return showRevericDialog<int>(
    context: context,
    builder: (_) => DialogFeedback.scope(
      builder: (_) =>
          _AgentRulePackDialog(databasePath: databasePath, novelId: novelId),
    ),
  );
}

class _AgentRulePackDialog extends HookConsumerWidget {
  const _AgentRulePackDialog({
    required this.databasePath,
    required this.novelId,
  });

  final String databasePath;
  final String novelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final packsFuture = useMemoized(() => loadAgentRulePacks(), const []);
    final packsSnapshot = useFuture(packsFuture);
    final packs = packsSnapshot.data ?? const <AgentRulePack>[];

    final currentRules =
        ref.watch(agentRulesStreamProvider(databasePath)).asData?.value ??
        const <AgentRule>[];
    final existingNames = {for (final rule in currentRules) rule.name};

    final search = useDebouncedSearch();
    final selectedPackId = useState<String?>(null);
    final selectedRuleIds = useState<Set<String>>(const {});
    final importing = useState(false);

    final filteredPacks = packs
        .where((pack) => pack.matchesQuery(search.query))
        .toList(growable: false);
    final selectedPack = packs
        .where((pack) => pack.id == selectedPackId.value)
        .firstOrNull;

    useEffect(() {
      selectedRuleIds.value = const {};
      return null;
    }, [selectedPackId.value]);

    final importableRules = (selectedPack?.rules ?? const <AgentRulePackRule>[])
        .where((rule) => !existingNames.contains(rule.name))
        .toList(growable: false);
    final selectedCount = selectedRuleIds.value.length;

    void toggleRule(String name) {
      final next = Set<String>.from(selectedRuleIds.value);
      if (!next.remove(name)) {
        next.add(name);
      }
      selectedRuleIds.value = next;
    }

    Future<void> doImport() async {
      final pack = selectedPack;
      if (pack == null || selectedCount == 0) {
        return;
      }
      importing.value = true;
      try {
        final imported = await importAgentRulePack(
          targetService: ref.read(novelContentServiceProvider(databasePath)),
          currentRules: currentRules,
          pack: AgentRulePack(
            id: pack.id,
            name: pack.name,
            summary: pack.summary,
            category: pack.category,
            rules: [
              for (final rule in pack.rules)
                if (selectedRuleIds.value.contains(rule.name)) rule,
            ],
          ),
          targetPath: databasePath,
        );
        if (context.mounted) {
          importing.value = false;
          Navigator.of(context).pop(imported);
        }
      } catch (error, stackTrace) {
        _log.error(
          'import rule pack failed pack=${pack.id} target=$databasePath',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          importing.value = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: DialogToast(
                variant: DialogToastVariant.error,
                child: Text(context.t(LocaleKeys.agentRulePackFailed)),
              ),
            ),
          );
        }
      }
    }

    return RevericDialog.panel(
      title: Row(
        children: [
          RevericIcon(RevericIcons.rule_outlined, size: 18, color: colors.accent),
          const SizedBox(width: RevericSpacing.sm),
          Text(context.t(LocaleKeys.agentRulePackLibrary)),
        ],
      ),
      content: DialogFeedback.surface(
        builder: (context) => SizedBox(
          width: 760,
          height: 480,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 260,
                child: _PackListColumn(
                  loading:
                      packsSnapshot.connectionState != ConnectionState.done &&
                      packs.isEmpty,
                  packs: filteredPacks,
                  hasAnyPack: packs.isNotEmpty,
                  searching: search.active,
                  searchController: search.controller,
                  selectedPackId: selectedPackId.value,
                  onSelect: (id) => selectedPackId.value = id,
                ),
              ),
              Container(
                width: RevericSizes.dividerThickness,
                margin: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.x2l,
                ),
                color: colors.border,
              ),
              Expanded(
                child: selectedPack == null
                    ? Center(
                        child: Text(
                          context.t(LocaleKeys.agentRulePackSelectHint),
                          style: typo.uiSmall.copyWith(color: colors.textMuted),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            selectedPack.name,
                            style: typo.uiSmallSemibold.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          if (selectedPack.summary.isNotEmpty) ...[
                            const SizedBox(height: RevericSpacing.xxs),
                            Text(
                              selectedPack.summary,
                              style: typo.uiTiny.copyWith(
                                color: colors.textMuted,
                                height: 1.45,
                              ),
                            ),
                          ],
                          const SizedBox(height: RevericSpacing.md),
                          Row(
                            children: [
                              Text(
                                context.t(
                                  LocaleKeys.commonSelectedCountFmt,
                                  namedArgs: {
                                    'count': '${selectedRuleIds.value.length}',
                                  },
                                ),
                                style: typo.uiTinySemibold.copyWith(
                                  color: colors.textSubtle,
                                ),
                              ),
                              const Spacer(),
                              RevericButton.secondary(
                                size: RevericButtonSize.compact,
                                label: context.t(LocaleKeys.commonSelectAll),
                                onPressed: () => selectedRuleIds.value = {
                                  for (final rule in importableRules) rule.name,
                                },
                              ),
                              const SizedBox(width: RevericSpacing.sm),
                              RevericButton.secondary(
                                size: RevericButtonSize.compact,
                                label: context.t(
                                  LocaleKeys.commonClearSelection,
                                ),
                                onPressed: () =>
                                    selectedRuleIds.value = const {},
                              ),
                            ],
                          ),
                          const SizedBox(height: RevericSpacing.sm),
                          Expanded(
                            child: ListView.builder(
                              itemCount: selectedPack.rules.length,
                              itemBuilder: (context, index) {
                                final rule = selectedPack.rules[index];
                                final exists = existingNames.contains(rule.name);
                                return _PackRuleRow(
                                  rule: rule,
                                  exists: exists,
                                  selected: selectedRuleIds.value.contains(
                                    rule.name,
                                  ),
                                  onTap: exists
                                      ? null
                                      : () => toggleRule(rule.name),
                                );
                              },
                            ),
                          ),
                          if (selectedPack.rules.any(
                            (rule) => existingNames.contains(rule.name),
                          )) ...[
                            const SizedBox(height: RevericSpacing.sm),
                            Text(
                              context.t(LocaleKeys.agentRuleCopyExistsHint),
                              style: typo.uiTiny.copyWith(
                                color: colors.textSubtle,
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: importing.value ? null : () => Navigator.of(context).pop(),
        ),
        RevericButton.primary(
          label: context.t(
            LocaleKeys.agentRulePackImport,
            namedArgs: {'count': '$selectedCount'},
          ),
          icon: RevericIcons.rule_outlined,
          loading: importing.value,
          onPressed: selectedCount == 0 ? null : doImport,
        ),
      ],
      width: 760 + RevericSpacing.x4l * 2,
    );
  }
}

class _PackListColumn extends StatelessWidget {
  const _PackListColumn({
    required this.loading,
    required this.packs,
    required this.hasAnyPack,
    required this.searching,
    required this.searchController,
    required this.selectedPackId,
    required this.onSelect,
  });

  final bool loading;
  final List<AgentRulePack> packs;
  final bool hasAnyPack;
  final bool searching;
  final TextEditingController searchController;
  final String? selectedPackId;
  final ValueChanged<String> onSelect;

  /// 包数量变多（小说 + 短剧）后，按 category 分段显示，避免一长条平铺。
  List<_PackGroupRow> get _groupedRows {
    final counts = <String, int>{};
    final order = <String>[];
    for (final pack in packs) {
      final key = _categoryOf(pack);
      if (!counts.containsKey(key)) {
        order.add(key);
        counts[key] = 0;
      }
      counts[key] = counts[key]! + 1;
    }
    final rows = <_PackGroupRow>[];
    for (final key in order) {
      rows.add(_PackGroupRow.header(key, counts[key]!));
      for (final pack in packs) {
        if (_categoryOf(pack) == key) {
          rows.add(_PackGroupRow.pack(pack));
        }
      }
    }
    return rows;
  }

  static String _categoryOf(AgentRulePack pack) =>
      pack.category.trim().isEmpty ? '其他' : pack.category.trim();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.t(LocaleKeys.agentRulePackLibrary),
          style: typo.uiTinySemibold.copyWith(color: colors.textSubtle),
        ),
        const SizedBox(height: RevericSpacing.sm),
        RevericSearchField(
          controller: searchController,
          hint: context.t(LocaleKeys.agentRulePackSearchHint),
          height: 34,
        ),
        const SizedBox(height: RevericSpacing.sm),
        Expanded(
          child: loading
              ? Center(
                  child: CircularProgressIndicator(color: colors.accent),
                )
              : packs.isEmpty
              ? Center(
                  child: Text(
                    context.t(
                      !hasAnyPack
                          ? LocaleKeys.agentRulePackEmpty
                          : searching
                          ? LocaleKeys.commonNoResults
                          : LocaleKeys.agentRulePackEmpty,
                    ),
                    textAlign: TextAlign.center,
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: _groupedRows.length,
                  itemBuilder: (context, index) {
                    final row = _groupedRows[index];
                    final pack = row.pack;
                    if (pack == null) {
                      return Padding(
                        padding: EdgeInsets.only(
                          top: index == 0 ? 0 : RevericSpacing.sm,
                          bottom: RevericSpacing.xxs,
                        ),
                        child: Text(
                          '${row.header}（${row.count}）',
                          style: typo.uiTinySemibold.copyWith(
                            color: colors.textSubtle,
                          ),
                        ),
                      );
                    }
                    return _PackListItem(
                      pack: pack,
                      active: pack.id == selectedPackId,
                      onTap: () => onSelect(pack.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PackGroupRow {
  const _PackGroupRow.header(this.header, this.count) : pack = null;
  const _PackGroupRow.pack(this.pack) : header = null, count = 0;

  final String? header;
  final int count;
  final AgentRulePack? pack;
}

class _PackListItem extends StatelessWidget {
  const _PackListItem({
    required this.pack,
    required this.active,
    required this.onTap,
  });

  final AgentRulePack pack;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.md,
          ),
          decoration: BoxDecoration(
            color: active ? colors.surfaceContainerHigh : Colors.transparent,
            border: Border.all(
              color: active ? colors.accent : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(RevericRadius.medium),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  RevericIcon(
                    RevericIcons.rule_outlined,
                    size: 14,
                    color: active ? colors.accent : colors.textMuted,
                  ),
                  const SizedBox(width: RevericSpacing.xs),
                  Expanded(
                    child: Text(
                      pack.name,
                      style: typo.uiSmall.copyWith(
                        color: active ? colors.textPrimary : colors.textSecondary,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.xs),
                  Text(
                    '${pack.rules.length}',
                    style: typo.uiTiny.copyWith(color: colors.textSubtle),
                  ),
                ],
              ),
              if (pack.summary.isNotEmpty) ...[
                const SizedBox(height: RevericSpacing.xxs),
                Text(
                  pack.summary,
                  style: typo.uiTiny.copyWith(
                    color: colors.textMuted,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PackRuleRow extends StatelessWidget {
  const _PackRuleRow({
    required this.rule,
    required this.exists,
    required this.selected,
    required this.onTap,
  });

  final AgentRulePackRule rule;
  final bool exists;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: Opacity(
          opacity: exists ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.all(RevericSpacing.md),
            decoration: BoxDecoration(
              color: selected ? colors.surfaceContainerHigh : colors.surface,
              border: Border.all(
                color: selected ? colors.accent : colors.borderInput,
              ),
              borderRadius: BorderRadius.circular(RevericRadius.medium),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PackCheckBox(checked: selected, disabled: exists),
                const SizedBox(width: RevericSpacing.sm),
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
                          if (exists) ...[
                            const SizedBox(width: RevericSpacing.sm),
                            Text(
                              context.t(LocaleKeys.agentRuleCopyExists),
                              style: typo.uiTiny.copyWith(
                                color: colors.textSubtle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: RevericSpacing.xxs),
                      Text(
                        rule.content,
                        style: typo.uiTiny.copyWith(
                          color: colors.textMuted,
                          height: 1.45,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PackCheckBox extends StatelessWidget {
  const _PackCheckBox({required this.checked, required this.disabled});

  final bool checked;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final borderColor = disabled ? colors.borderSubtle : colors.borderInput;

    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: checked ? colors.accent : Colors.transparent,
        border: Border.all(
          color: checked ? colors.accent : borderColor,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(RevericRadius.small),
      ),
      child: checked
          ? RevericIcon(RevericIcons.check, size: 12, color: colors.onAccent)
          : null,
    );
  }
}
