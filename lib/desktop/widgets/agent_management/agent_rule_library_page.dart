// 职责: 规则库整页浏览与导入 — 左分类、中规则包、右包内规则勾选，支持跨包汇总后一次导入。
// 关联文件:
//   assets/rule_packs/rule_packs.json
//   assets/rule_packs/short_drama_packs.json
//   lib/shared/models/agent_rule_pack.dart
//   lib/shared/services/agent_rule_pack_service.dart
//   lib/desktop/widgets/agent_management/agent_rules_grid_page.dart
//   lib/shared/providers/agent_rule_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_rule.json
//   assets/translations/zh-CN/agent_rule.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/hooks.md
//   .agents/rules/search-debounce.md
//   .agents/rules/error-handling.md
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/dialog_feedback.dart';
import '../../../shared/components/reveric_button.dart';
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
import 'home_management_cards.dart';

final _log = AppLogger.forModule('AgentRuleLibrary');

/// 打开规则库整页；返回实际导入条数，未导入返回 null。
///
/// 页面是独立路由，标题栏拖拽区必须用本页自己的 GlobalKey：复用来源页的
/// GlobalKey 会让同一 key 同时挂在两个路由上，触发框架重复挂载断言。
Future<int?> showAgentRuleLibraryPage({
  required BuildContext context,
  required String databasePath,
  required String novelId,
}) {
  return Navigator.of(context).push<int>(
    MaterialPageRoute<int>(
      builder: (routeContext) =>
          AgentRuleLibraryPage(databasePath: databasePath, novelId: novelId),
    ),
  );
}

class AgentRuleLibraryPage extends HookConsumerWidget {
  const AgentRuleLibraryPage({
    super.key,
    required this.databasePath,
    required this.novelId,
  });

  final String databasePath;
  final String novelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final headerGestureExclusionKey = useMemoized(GlobalKey.new, const []);

    final reloadTick = useState(0);
    final packsFuture = useMemoized(
      () => loadAgentRulePacks(refresh: reloadTick.value > 0),
      [reloadTick.value],
    );
    final packsSnapshot = useFuture(packsFuture);
    final packs = packsSnapshot.data ?? const <AgentRulePack>[];

    final status = useState<AgentRulePackLibraryStatus?>(null);
    final checking = useState(false);
    useEffect(() {
      var active = true;
      describeAgentRulePackLibrary().then((value) {
        if (active) {
          status.value = value;
        }
      });
      return () => active = false;
    }, [reloadTick.value]);

    final currentRules =
        ref.watch(agentRulesStreamProvider(databasePath)).asData?.value ??
        const <AgentRule>[];
    final existingNames = {for (final rule in currentRules) rule.name};

    final search = useDebouncedSearch();
    final category = useState<String?>(null);
    final packId = useState<String?>(null);
    final selection = useState<Map<String, Set<String>>>(const {});
    final importing = useState(false);

    final categories = _categoryCounts(packs);
    final visiblePacks = packs
        .where(
          (pack) => category.value == null || pack.category == category.value,
        )
        .where((pack) => pack.matchesQuery(search.query))
        .toList(growable: false);
    final selectedPack = packs
        .where((pack) => pack.id == packId.value)
        .firstOrNull;

    int selectedTotal() =>
        selection.value.values.fold(0, (sum, names) => sum + names.length);

    void toggle(String packKey, String ruleName) {
      final next = Map<String, Set<String>>.from(selection.value);
      final set = Set<String>.from(next[packKey] ?? const <String>{});
      if (!set.remove(ruleName)) {
        set.add(ruleName);
      }
      if (set.isEmpty) {
        next.remove(packKey);
      } else {
        next[packKey] = set;
      }
      selection.value = next;
    }

    Future<void> importSelected() async {
      final total = selectedTotal();
      if (total == 0) {
        return;
      }
      final rules = <AgentRulePackRule>[];
      for (final pack in packs) {
        final names = selection.value[pack.id];
        if (names == null) {
          continue;
        }
        for (final rule in pack.rules) {
          if (names.contains(rule.name) && !existingNames.contains(rule.name)) {
            rules.add(rule);
          }
        }
      }
      if (rules.isEmpty) {
        return;
      }
      importing.value = true;
      try {
        final imported = await importAgentRulePack(
          targetService: ref.read(novelContentServiceProvider(databasePath)),
          currentRules: currentRules,
          pack: AgentRulePack(
            id: 'library_batch',
            name: '规则库',
            summary: '',
            category: '',
            rules: rules,
          ),
          targetPath: databasePath,
        );
        if (context.mounted) {
          importing.value = false;
          Navigator.of(context).pop(imported);
        }
      } catch (error, stackTrace) {
        _log.error(
          'import rule library failed target=$databasePath',
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

    Future<void> checkUpdates() async {
      if (checking.value) {
        return;
      }
      checking.value = true;
      final result = await refreshAgentRulePacks();
      if (!context.mounted) {
        return;
      }
      checking.value = false;
      if (result.outcome == AgentRulePackUpdateOutcome.updated) {
        reloadTick.value = reloadTick.value + 1;
        _showToast(
          context,
          DialogToastVariant.success,
          context.t(
            LocaleKeys.agentRulePackUpdated,
            namedArgs: {'version': '${result.version}'},
          ),
        );
      } else if (result.outcome == AgentRulePackUpdateOutcome.latest) {
        _showToast(
          context,
          DialogToastVariant.info,
          context.t(
            LocaleKeys.agentRulePackUpToDate,
            namedArgs: {'version': '${result.version}'},
          ),
        );
      } else {
        _showToast(
          context,
          DialogToastVariant.error,
          context.t(LocaleKeys.agentRulePackUpdateFailed),
        );
      }
    }

    final statusValue = status.value;
    final versionLabel = statusValue == null
        ? ''
        : '${context.t(LocaleKeys.agentRulePackVersion, namedArgs: {'version': '${statusValue.version}', 'packs': '${statusValue.packCount}', 'rules': '${statusValue.ruleCount}'})} · ${context.t(statusValue.isHotUpdate ? LocaleKeys.agentRulePackSourceHot : LocaleKeys.agentRulePackSourceBundled)}';

    return Material(
      color: colors.canvas,
      child: HomeManagementScaffold(
        headerGestureExclusionKey: headerGestureExclusionKey,
        icon: RevericIcons.rule_outlined,
        titleKey: LocaleKeys.agentRulePackLibrary,
        onBack: () => Navigator.of(context).pop(),
        secondaryAction: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (versionLabel.isNotEmpty)
              Text(
                versionLabel,
                style: RevericTheme.typographyOf(
                  context,
                ).uiTiny.copyWith(color: colors.textSubtle),
              ),
            const SizedBox(width: RevericSpacing.sm),
            TextButton.icon(
              onPressed: checking.value
                  ? null
                  : () => unawaited(checkUpdates()),
              icon: const RevericIcon(RevericIcons.arrow_clockwise, size: 14),
              label: Text(
                context.t(
                  checking.value
                      ? LocaleKeys.agentRulePackChecking
                      : LocaleKeys.agentRulePackCheckUpdate,
                ),
              ),
            ),
          ],
        ),
        child:
            packsSnapshot.connectionState != ConnectionState.done &&
                packs.isEmpty
            ? const HomeManagementLoadingState()
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 232,
                    child: _LibraryCategoryColumn(
                      packs: packs,
                      counts: categories,
                      selected: category.value,
                      onSelect: (value) {
                        category.value = value;
                        final first = packs
                            .where(
                              (pack) => value == null || pack.category == value,
                            )
                            .firstOrNull;
                        packId.value = first?.id;
                        search.controller.clear();
                      },
                    ),
                  ),
                  _VerticalRule(color: colors.border),
                  SizedBox(
                    width: 392,
                    child: _LibraryPackColumn(
                      packs: visiblePacks,
                      allPacks: packs,
                      categoryLabel: category.value,
                      search: search,
                      selectedPackId: packId.value,
                      importedCountOf: (pack) => pack.rules
                          .where((rule) => existingNames.contains(rule.name))
                          .length,
                      onSelect: (id) {
                        packId.value = id;
                      },
                    ),
                  ),
                  _VerticalRule(color: colors.border),
                  Expanded(
                    child: _LibraryDetailColumn(
                      packs: packs,
                      pack: selectedPack,
                      existingNames: existingNames,
                      selection: selection.value,
                      total: selectedTotal(),
                      importing: importing.value,
                      onToggle: toggle,
                      onSelectAll: (pack) {
                        final free = [
                          for (final rule in pack.rules)
                            if (!existingNames.contains(rule.name)) rule.name,
                        ];
                        final next = Map<String, Set<String>>.from(
                          selection.value,
                        );
                        final current = next[pack.id];
                        if (current != null && free.every(current.contains)) {
                          next.remove(pack.id);
                        } else {
                          next[pack.id] = free.toSet();
                        }
                        selection.value = next;
                      },
                      onClear: () => selection.value = const {},
                      onImport: () => unawaited(importSelected()),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

void _showToast(BuildContext context, DialogToastVariant variant, String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: DialogToast(variant: variant, child: Text(text)),
    ),
  );
}

Map<String, int> _categoryCounts(List<AgentRulePack> packs) {
  final counts = <String, int>{};
  for (final pack in packs) {
    final key = pack.category.trim().isEmpty ? '其他' : pack.category.trim();
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

class _VerticalRule extends StatelessWidget {
  const _VerticalRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: RevericSizes.dividerThickness, color: color);
  }
}

class _LibraryCategoryColumn extends StatelessWidget {
  const _LibraryCategoryColumn({
    required this.packs,
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final List<AgentRulePack> packs;
  final Map<String, int> counts;
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
            context.t(LocaleKeys.agentRulePackCategoryTitle),
            style: typo.uiTinySemibold.copyWith(color: colors.textSubtle),
          ),
          const SizedBox(height: RevericSpacing.xs),
          _CategoryRow(
            label: context.t(LocaleKeys.agentRulePackCategoryAll),
            count: packs.length,
            active: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final entry in counts.entries)
            _CategoryRow(
              label: entry.key,
              count: entry.value,
              active: selected == entry.key,
              onTap: () => onSelect(entry.key),
            ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
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

class _LibraryPackColumn extends StatelessWidget {
  const _LibraryPackColumn({
    required this.packs,
    required this.allPacks,
    required this.categoryLabel,
    required this.search,
    required this.selectedPackId,
    required this.importedCountOf,
    required this.onSelect,
  });

  final List<AgentRulePack> packs;
  final List<AgentRulePack> allPacks;
  final String? categoryLabel;
  final DebouncedSearch search;
  final String? selectedPackId;
  final int Function(AgentRulePack pack) importedCountOf;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Padding(
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
                categoryLabel ?? context.t(LocaleKeys.agentRulePackCategoryAll),
                style: typo.uiTinySemibold.copyWith(color: colors.textSubtle),
              ),
              const Spacer(),
              Text(
                '${packs.length}',
                style: typo.uiTiny.copyWith(color: colors.textSubtle),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          RevericSearchField(
            controller: search.controller,
            hint: context.t(LocaleKeys.agentRulePackSearchHint),
            height: 34,
          ),
          const SizedBox(height: RevericSpacing.sm),
          Expanded(
            child: packs.isEmpty
                ? Center(
                    child: Text(
                      context.t(
                        allPacks.isEmpty
                            ? LocaleKeys.agentRulePackEmpty
                            : LocaleKeys.commonNoResults,
                      ),
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: packs.length,
                    itemBuilder: (context, index) {
                      final pack = packs[index];
                      return _PackCard(
                        pack: pack,
                        imported: importedCountOf(pack),
                        active: pack.id == selectedPackId,
                        onTap: () => onSelect(pack.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.pack,
    required this.imported,
    required this.active,
    required this.onTap,
  });

  final AgentRulePack pack;
  final int imported;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final allImported = imported >= pack.rules.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        hoverColor: colors.hover,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.md,
          ),
          decoration: BoxDecoration(
            color: active ? colors.surfaceContainerHigh : colors.surface,
            border: Border.all(
              color: active ? colors.accent : colors.borderInput,
            ),
            borderRadius: BorderRadius.circular(RevericRadius.medium),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      pack.name,
                      style: typo.uiSmallSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  Text(
                    imported == 0
                        ? '${pack.rules.length}'
                        : context.t(
                            LocaleKeys.agentRulePackImportedCount,
                            namedArgs: {
                              'imported': '$imported',
                              'total': '${pack.rules.length}',
                            },
                          ),
                    style: typo.uiTiny.copyWith(
                      color: allImported ? colors.accent : colors.textSubtle,
                    ),
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

class _LibraryDetailColumn extends StatelessWidget {
  const _LibraryDetailColumn({
    required this.packs,
    required this.pack,
    required this.existingNames,
    required this.selection,
    required this.total,
    required this.importing,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClear,
    required this.onImport,
  });

  final List<AgentRulePack> packs;
  final AgentRulePack? pack;
  final Set<String> existingNames;
  final Map<String, Set<String>> selection;
  final int total;
  final bool importing;
  final void Function(String packId, String ruleName) onToggle;
  final ValueChanged<AgentRulePack> onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final current = pack;
    final chips = [
      for (final candidate in packs)
        if ((selection[candidate.id]?.length ?? 0) > 0)
          (name: candidate.name, count: selection[candidate.id]!.length),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CartBar(chips: chips, total: total, onClear: onClear),
        Expanded(
          child: current == null
              ? Center(
                  child: Text(
                    context.t(LocaleKeys.agentRulePackSelectHint),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(
                    RevericSpacing.x2l,
                    RevericSpacing.x2l,
                    RevericSpacing.x2l,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              current.name,
                              style: typo.heading2.copyWith(
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: RevericSpacing.sm),
                          Text(
                            context.t(
                              LocaleKeys.agentRulePackRuleCount,
                              namedArgs: {'count': '${current.rules.length}'},
                            ),
                            style: typo.uiTiny.copyWith(
                              color: colors.textSubtle,
                            ),
                          ),
                        ],
                      ),
                      if (current.summary.isNotEmpty) ...[
                        const SizedBox(height: RevericSpacing.xxs),
                        Text(
                          current.summary,
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
                            context.t(LocaleKeys.agentRulePackRulesTitle),
                            style: typo.uiTinySemibold.copyWith(
                              color: colors.textSubtle,
                            ),
                          ),
                          const Spacer(),
                          _LinkText(
                            label: context.t(
                              LocaleKeys.agentRulePackSelectAllImportable,
                              namedArgs: {
                                'count':
                                    '${current.rules.where((rule) => !existingNames.contains(rule.name)).length}',
                              },
                            ),
                            onTap: () => onSelectAll(current),
                          ),
                        ],
                      ),
                      const SizedBox(height: RevericSpacing.xs),
                      Expanded(
                        child: ListView.builder(
                          itemCount: current.rules.length,
                          itemBuilder: (context, index) {
                            final rule = current.rules[index];
                            final exists = existingNames.contains(rule.name);
                            final checked =
                                selection[current.id]?.contains(rule.name) ??
                                false;
                            return _LibraryRuleRow(
                              rule: rule,
                              exists: exists,
                              checked: checked,
                              onTap: exists
                                  ? null
                                  : () => onToggle(current.id, rule.name),
                            );
                          },
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
              RevericButton.primary(
                label: context.t(
                  LocaleKeys.agentRulePackImport,
                  namedArgs: {'count': '$total'},
                ),
                icon: RevericIcons.rule_outlined,
                loading: importing,
                size: RevericButtonSize.compact,
                onPressed: total == 0 || current == null ? null : onImport,
              ),
              const SizedBox(width: RevericSpacing.md),
              Text(
                context.t(LocaleKeys.agentRulePackCartHint),
                style: typo.uiTiny.copyWith(color: colors.textSubtle),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.chips,
    required this.total,
    required this.onClear,
  });

  final List<({String name, int count})> chips;
  final int total;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
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
          Text(
            context.t(
              LocaleKeys.agentRulePackSelectedTotal,
              namedArgs: {'count': '$total'},
            ),
            style: typo.uiTinySemibold.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final chip in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: RevericSpacing.xxs),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: RevericSpacing.sm,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          border: Border.all(color: colors.borderInput),
                          borderRadius: BorderRadius.circular(
                            RevericRadius.small,
                          ),
                        ),
                        child: Text(
                          '${chip.name} · ${chip.count}',
                          style: typo.uiTiny.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (total > 0)
            _LinkText(
              label: context.t(LocaleKeys.commonClearSelection),
              onTap: onClear,
            ),
        ],
      ),
    );
  }
}

class _LibraryRuleRow extends StatelessWidget {
  const _LibraryRuleRow({
    required this.rule,
    required this.exists,
    required this.checked,
    required this.onTap,
  });

  final AgentRulePackRule rule;
  final bool exists;
  final bool checked;
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
        hoverColor: exists ? Colors.transparent : colors.hover,
        child: Opacity(
          opacity: exists ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.all(RevericSpacing.md),
            decoration: BoxDecoration(
              color: checked ? colors.surfaceContainerHigh : colors.surface,
              border: Border.all(
                color: checked ? colors.accent : colors.borderInput,
              ),
              borderRadius: BorderRadius.circular(RevericRadius.medium),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LibraryCheckBox(checked: checked, disabled: exists),
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

class _LibraryCheckBox extends StatelessWidget {
  const _LibraryCheckBox({required this.checked, required this.disabled});

  final bool checked;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: checked ? colors.accent : Colors.transparent,
        border: Border.all(
          color: checked
              ? colors.accent
              : (disabled ? colors.borderSubtle : colors.borderInput),
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

class _LinkText extends StatelessWidget {
  const _LinkText({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.xxs,
          vertical: RevericSpacing.xxs,
        ),
        child: Text(
          label,
          style: RevericTheme.typographyOf(
            context,
          ).uiTiny.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}
