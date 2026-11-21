// 职责: 最近 AI 变更日志卡片 — 桌面 chrome（头部计数/查看明细/折叠/关闭），body 内嵌共享 RecentChangesLog。
// 关联文件:
//   lib/shared/widgets/ai/diff/recent_changes_log.dart
//   lib/desktop/widgets/ai/diff/pending_changes_detail_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/components/reveric_button.dart';
import '../../../../shared/components/reveric_icon_button.dart';
import '../../../../shared/components/reveric_surfaces.dart';
import '../../../../shared/database/novel_content_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/theme/theme.dart';
import '../../../../shared/providers/novel_providers.dart';
import '../../../../shared/services/working_overlay.dart';
import '../../../../shared/widgets/ai/diff/recent_changes_log.dart';
import 'pending_changes_detail_dialog.dart';

class PendingChangesSummaryCard extends ConsumerStatefulWidget {
  const PendingChangesSummaryCard({
    super.key,
    required this.databasePath,
    required this.changes,
    this.onClose,
    this.initialExpanded = false,
    this.margin = const EdgeInsets.fromLTRB(
      RevericSpacing.x2l,
      0,
      RevericSpacing.x2l,
      RevericSpacing.sm,
    ),
  });

  final String databasePath;
  final List<WorkingChange> changes;
  final VoidCallback? onClose;
  final bool initialExpanded;

  /// 默认与桌面 Composer 输入框及后台任务条等宽；独立侧栏可覆盖外边距。
  final EdgeInsets margin;

  @override
  ConsumerState<PendingChangesSummaryCard> createState() =>
      _PendingChangesSummaryCardState();
}

class _PendingChangesSummaryCardState
    extends ConsumerState<PendingChangesSummaryCard> {
  late bool _expanded;

  /// 「撤销本轮」：把这一轮所有待处理 AI 变更逐条拒绝，等于整轮回滚。
  /// 与「查看变更」里的逐条采用/拒绝是同一底层动作，不是另一套逻辑。
  Future<void> _revertAll() async {
    final service = ref.read(
      workingOverlayServiceProvider(widget.databasePath),
    );
    var reverted = 0;
    for (final change in widget.changes) {
      try {
        await service.rejectWorkingChange(change.id);
        reverted++;
      } catch (_) {
        // 单条失败不影响其余条目——撤销要尽量回到干净状态。
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.t(
            LocaleKeys.workspaceRevertRoundDone,
            namedArgs: {'count': '$reverted'},
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.changes.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final groupCount = countChangeGroups(widget.changes);

    return RevericElevatedCard(
      fallback: colors.surface,
      margin: widget.margin,
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: _expanded,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                // 头部没有独立底色，不撑最小高度会比后台任务条的汇总行矮一截。
                constraints: const BoxConstraints(
                  minHeight: RevericSizes.iconButtonSize,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: RevericSpacing.lg,
                    // 卡片边框占 1px；Composer 的 DecoratedBox 不占布局空间。
                    right: RevericSpacing.sm - RevericSizes.dividerThickness,
                  ),
                  child: Row(
                    children: [
                      RevericIcon(
                        RevericIcons.history_outlined,
                        // 与后台任务条的状态点同直径，两张卡的文字列对齐。
                        size: RevericSizes.agentDotSize,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: RevericSpacing.sm),
                      // 标题和计数合占唯一一个 Expanded：行内再留第二个弹性槽，
                      // 剩余宽度会被平分，标题在还有空位时就被截断、计数被挤没。
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                context.t(LocaleKeys.workspaceRecentChanges),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: typo.ui.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: RevericSpacing.sm),
                            Flexible(
                              child: Text(
                                '· $groupCount ${context.t(LocaleKeys.commonItemUnit)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: typo.uiSmall.copyWith(
                                  color: colors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      RevericButton.text(
                        label: context.t(LocaleKeys.workspaceRevertRound),
                        size: RevericButtonSize.compact,
                        onPressed: _revertAll,
                      ),
                      RevericButton.text(
                        label: context.t(LocaleKeys.workspaceViewChanges),
                        size: RevericButtonSize.compact,
                        onPressed: () =>
                            PendingChangesDetailDialog.showFromChanges(
                              context,
                              databasePath: widget.databasePath,
                              changes: widget.changes,
                            ),
                      ),
                      // 折叠箭头本身不是按钮（整行可点），但占满一个控件槽，
                      // 才能和后台任务条行尾的控件落在同一条竖线上。
                      SizedBox(
                        width: RevericSizes.iconButtonSize,
                        child: Center(
                          child: RevericIcon(
                            _expanded
                                ? RevericIcons.expand_less_rounded
                                : RevericIcons.expand_more_rounded,
                            size: RevericSizes.iconButtonIconSize,
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                      if (widget.onClose != null)
                        RevericIconButton(
                          icon: RevericIcons.close_rounded,
                          onPressed: widget.onClose!,
                          tooltip: context.t(LocaleKeys.commonCancel),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              // 卡片自己负责底色：这里再铺一层不透明 surface 会盖掉毛玻璃。
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.lg,
                0,
                RevericSpacing.lg,
                RevericSpacing.lg,
              ),
              child: RecentChangesLog(
                databasePath: widget.databasePath,
                changes: widget.changes,
                enableNavigation: true,
              ),
            ),
        ],
      ),
    );
  }
}
