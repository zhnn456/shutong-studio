// 职责: 骨架看板 — 按卷展示"每一章写了什么、缺什么"的可视化面板。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_overview.dart（入口按钮）
//   lib/shared/models/chapter.dart（数据来源：chapter_nodes 的元数据流）
//   lib/shared/localization/locale_keys.dart
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//
// 数据全部来自已加载的章节树（chapters），不新增查询、不新增状态：
// 卷 = isVolume；章 = 其余章节，按 parentId 归属；章号用 chapterNum（全书连续）。
// 缺口判定与概览页同口径：无章纲 / 有正文未沉淀 / 字数远低于目标。

import 'package:flutter/material.dart';

import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/chapter.dart';
import '../../../shared/services/novel_goal.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/components/reveric_button.dart';

/// 一卷的统计。
class _VolumeStats {
  _VolumeStats(this.volume, this.chapters);

  final Chapter? volume;
  final List<Chapter> chapters;

  int get withOutline =>
      chapters.where((chapter) => chapter.outline.trim().isNotEmpty).length;

  int get written => chapters
      .where((chapter) =>
          chapter.wordCount > 0 || chapter.content.trim().isNotEmpty)
      .length;

  int get settled => chapters
      .where((chapter) => normalizeChapterStat(chapter.stat) != chapterStatDraft)
      .length;

  int get words =>
      chapters.fold<int>(0, (sum, chapter) => sum + chapter.wordCount);

  double get progress => chapters.isEmpty ? 0 : written / chapters.length;
}

/// 骨架看板主体（放入 Dialog 使用）。
class SkeletonBoardPage extends StatefulWidget {
  const SkeletonBoardPage({
    super.key,
    required this.chapters,
    this.goal,
  });

  final List<Chapter> chapters;
  final NovelGoal? goal;

  @override
  State<SkeletonBoardPage> createState() => _SkeletonBoardPageState();
}

class _SkeletonBoardPageState extends State<SkeletonBoardPage> {
  String? _selectedVolumeId;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final volumes = widget.chapters.where((chapter) => chapter.isVolume).toList()
      ..sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));
    final bodyChapters = widget.chapters
        .where((chapter) => !chapter.isVolume)
        .toList()
      ..sort((a, b) => a.siblingOrder.compareTo(b.siblingOrder));

    final groups = <_VolumeStats>[];
    if (volumes.isEmpty) {
      groups.add(_VolumeStats(null, bodyChapters));
    } else {
      for (final volume in volumes) {
        groups.add(
          _VolumeStats(
            volume,
            bodyChapters
                .where((chapter) => (chapter.parentId ?? '') == volume.id)
                .toList(),
          ),
        );
      }
      final orphans =
          bodyChapters.where((chapter) => chapter.parentId == null).toList();
      if (orphans.isNotEmpty) {
        groups.add(_VolumeStats(null, orphans));
      }
    }

    if (_selectedVolumeId == null && groups.isNotEmpty) {
      _selectedVolumeId = groups.first.volume?.id ?? '__root__';
    }

    final selected = groups.firstWhere(
      (group) =>
          (group.volume?.id ?? '__root__') == _selectedVolumeId,
      orElse: () => groups.isEmpty
          ? _VolumeStats(null, const <Chapter>[])
          : groups.first,
    );

    final totalWritten = bodyChapters
        .where((chapter) =>
            chapter.wordCount > 0 || chapter.content.trim().isNotEmpty)
        .length;
    final totalSettled = bodyChapters
        .where((chapter) => normalizeChapterStat(chapter.stat) != chapterStatDraft)
        .length;
    final totalWords =
        bodyChapters.fold<int>(0, (sum, chapter) => sum + chapter.wordCount);

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        width: 1040,
        height: 720,
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.x4l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    context.t(LocaleKeys.workspaceSkeletonBoardTitle),
                    style: typo.heading2.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(width: RevericSpacing.md),
                  Expanded(
                    child: Text(
                      context.t(
                        LocaleKeys.workspaceSkeletonBoardSummary,
                        namedArgs: {
                          'chapters': '${bodyChapters.length}',
                          'written': '$totalWritten',
                          'settled': '$totalSettled',
                          'words': _formatWords(totalWords),
                        },
                      ),
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                  ),
                  RevericButton.text(
                    label: context.t(LocaleKeys.workspaceSkeletonBoardClose),
                    size: RevericButtonSize.compact,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: RevericSpacing.xs),
              Text(
                context.t(LocaleKeys.workspaceSkeletonBoardHint),
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: RevericSpacing.x3l),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 268,
                      child: ListView.separated(
                        itemCount: groups.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: RevericSpacing.sm),
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          final id = group.volume?.id ?? '__root__';
                          return _VolumeCard(
                            stats: group,
                            selected: id == _selectedVolumeId,
                            label: group.volume == null
                                ? context
                                    .t(LocaleKeys.workspaceSkeletonBoardAllBook)
                                : group.volume!.displayTitle,
                            onTap: () =>
                                setState(() => _selectedVolumeId = id),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: RevericSpacing.x3l),
                    Expanded(
                      child: _ChapterList(
                        chapters: selected.chapters,
                        goal: widget.goal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatWords(int words) {
  if (words >= 10000) {
    return '${(words / 10000).toStringAsFixed(1)} 万';
  }
  return '$words';
}

class _VolumeCard extends StatelessWidget {
  const _VolumeCard({
    required this.stats,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final _VolumeStats stats;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(RevericSpacing.lg),
        decoration: BoxDecoration(
          color: selected
              ? colors.surfaceContainerHigh
              : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colors.accentWarm : colors.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.xs),
            Text(
              context.t(
                LocaleKeys.workspaceSkeletonBoardVolumeStats,
                namedArgs: {
                  'chapters': '${stats.chapters.length}',
                  'written': '${stats.written}',
                  'words': _formatWords(stats.words),
                },
              ),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: RevericSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: stats.progress,
                minHeight: 4,
                backgroundColor: colors.borderSubtle,
              ),
            ),
            const SizedBox(height: RevericSpacing.xs),
            Text(
              context.t(
                LocaleKeys.workspaceSkeletonBoardVolumeDetail,
                namedArgs: {
                  'outline': '${stats.withOutline}',
                  'settled': '${stats.settled}',
                },
              ),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterList extends StatelessWidget {
  const _ChapterList({required this.chapters, this.goal});

  final List<Chapter> chapters;
  final NovelGoal? goal;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    if (chapters.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          context.t(LocaleKeys.workspaceSkeletonBoardEmpty),
          style: typo.body.copyWith(color: colors.textMuted),
        ),
      );
    }

    final perChapterWords = goal?.wordsPerChapter ?? 0;

    return ListView.separated(
      itemCount: chapters.length,
      separatorBuilder: (_, _) => Container(
        height: 1,
        color: colors.borderSubtle.withValues(alpha: 0.5),
      ),
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final stat = normalizeChapterStat(chapter.stat);
        final written =
            chapter.wordCount > 0 || chapter.content.trim().isNotEmpty;
        final hasOutline = chapter.outline.trim().isNotEmpty;
        final brief = chapter.brief.trim();
        final thinWords = written &&
            perChapterWords > 0 &&
            chapter.wordCount < perChapterWords * 0.6;

        return Padding(
          padding: const EdgeInsets.symmetric(
            vertical: RevericSpacing.md,
            horizontal: RevericSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '${chapter.chapterNum ?? ''}',
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chapter.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typo.uiSemibold.copyWith(
                        color: hasOutline ? colors.textPrimary : colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: RevericSpacing.xxs),
                    Text(
                      brief.isEmpty
                          ? (chapter.outline.trim().isEmpty
                              ? context.t(LocaleKeys.workspaceSkeletonBoardNoBrief)
                              : chapter.outline.trim())
                          : brief,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: typo.uiSmall.copyWith(color: colors.textSecondary),
                    ),
                    if (!hasOutline ||
                        (written && stat != chapterStatReviewed) ||
                        thinWords)
                      Padding(
                        padding: const EdgeInsets.only(top: RevericSpacing.xxs),
                        child: Wrap(
                          spacing: RevericSpacing.xs,
                          children: [
                            if (!hasOutline) _GapChip(
                              label: context
                                  .t(LocaleKeys.workspaceSkeletonBoardGapOutline),
                            ),
                            if (written && stat != chapterStatReviewed)
                              _GapChip(
                                label: context
                                    .t(LocaleKeys.workspaceSkeletonBoardGapSettle),
                                warn: true,
                              ),
                            if (thinWords)
                              _GapChip(
                                label: context.t(
                                  LocaleKeys.workspaceSkeletonBoardGapWords,
                                  namedArgs: {'words': '$perChapterWords'},
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: RevericSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    written
                        ? '${chapter.wordCount} 字'
                        : context.t(LocaleKeys.workspaceSkeletonBoardUnwritten),
                    style: typo.uiSmall.copyWith(
                      color: written ? colors.textSecondary : colors.textMuted,
                    ),
                  ),
                  if (written)
                    Padding(
                      padding: const EdgeInsets.only(top: RevericSpacing.xxs),
                      child: Text(
                        context.t(
                          stat == chapterStatReviewed || stat == chapterStatPublished
                              ? LocaleKeys.workspaceSkeletonBoardStatSettled
                              : LocaleKeys.workspaceSkeletonBoardStatDraft,
                        ),
                        style: typo.uiSmall.copyWith(
                          color: stat == chapterStatReviewed ||
                                  stat == chapterStatPublished
                              ? colors.accentWarm
                              : colors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GapChip extends StatelessWidget {
  const _GapChip({required this.label, this.warn = false});

  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (warn ? colors.accentWarm : colors.textMuted).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: typo.uiSmall.copyWith(
          color: warn ? colors.accentWarm : colors.textMuted,
        ),
      ),
    );
  }
}
