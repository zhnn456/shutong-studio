// 职责: 桌面端小说概览页 — 标题/标签、继续写作 hero、项目简介与灵感片段、写作入口卡片
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/shared/models/novel_workspace.dart
//   lib/shared/database/app_database.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_surfaces.dart';
import '../../../shared/components/reveric_context_menu.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/content_kind.dart';
import '../../../shared/models/content_status.dart';
import '../../../shared/models/novel_workspace.dart';
import '../../../shared/models/outline.dart';
import '../../../shared/services/chapter_cast.dart';
import '../../../shared/services/novel_goal.dart';
import '../../../shared/theme/theme.dart';
import '../agent_management/agent_model_settings_page.dart';
import '../novel_create_submitter.dart';
import 'hero.dart';
import '../../../shared/widgets/media_asset_image.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int _coverThumbnailCacheWidth = 240;

class NovelOverview extends StatelessWidget {
  const NovelOverview({
    super.key,
    required this.novel,
    required this.chapters,
    this.lastWrittenChapter,
    required this.characterProfiles,
    required this.worldbuildingEntries,
    required this.outlineEntries,
    required this.foreshadowings,
    required this.canOpenCoverStudio,
    required this.onOpenCoverStudio,
    required this.onUploadCover,
    required this.onSelectionChanged,
    required this.onContinueWriting,
    this.onEditNovel,
    required this.coverThumbnailKey,
    required this.coverMenuTrigger,
    this.goal,
    this.onEditGoal,
    this.onPlanChapters,
    this.onEditStyle,
    this.onKickoff,
  });

  final Novel novel;
  final List<Chapter> chapters;
  final Chapter? lastWrittenChapter;
  final List<CharacterProfile> characterProfiles;
  final List<Document> worldbuildingEntries;
  final List<OutlineDraft> outlineEntries;
  final List<Foreshadowing> foreshadowings;
  final bool canOpenCoverStudio;
  final VoidCallback onOpenCoverStudio;
  final VoidCallback onUploadCover;
  final ValueSetter<WorkspaceSelection> onSelectionChanged;
  final ValueChanged<String> onContinueWriting;
  final VoidCallback? onEditNovel;
  final GlobalKey coverThumbnailKey;
  final ValueNotifier<int> coverMenuTrigger;

  /// 全书目标（章数 / 每章字数）。null 表示还没设定。
  final NovelGoal? goal;
  final VoidCallback? onEditGoal;

  /// 按目标把后续章节（含字段章纲）一次性补齐。
  final VoidCallback? onPlanChapters;

  /// 文风样文入口（贴自己的文字，让 AI 照着腔调写）。
  final VoidCallback? onEditStyle;

  /// 「一键起稿」：把简介 + 目标交给 AI，一次建人物卡与前 10 章骨架。
  final VoidCallback? onKickoff;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x6l,
        vertical: RevericSpacing.x5l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleSection(novel: novel, onEditNovel: onEditNovel),
          const SizedBox(height: RevericSpacing.x4l),
          ContinueWritingHero(
            onContinueWriting: onContinueWriting,
            chapters: chapters,
            lastWrittenChapter: lastWrittenChapter,
            onSelectionChanged: onSelectionChanged,
            hasAnyFoundation:
                characterProfiles.isNotEmpty ||
                worldbuildingEntries.isNotEmpty ||
                outlineEntries.isNotEmpty,
          ),
          const SizedBox(height: RevericSpacing.x4l),
          _FlowProgressCard(
            novel: novel,
            characterProfiles: characterProfiles,
            worldbuildingEntries: worldbuildingEntries,
            outlineEntries: outlineEntries,
            chapters: chapters,
            foreshadowings: foreshadowings,
            goal: goal,
            onSelectionChanged: onSelectionChanged,
            onPlanChapters: onPlanChapters,
          ),
          const SizedBox(height: RevericSpacing.x4l),
          _SecondRow(
            novel: novel,
            chapters: chapters,
            characterProfiles: characterProfiles,
            worldbuildingEntries: worldbuildingEntries,
            foreshadowings: foreshadowings,
            canOpenCoverStudio: canOpenCoverStudio,
            onOpenCoverStudio: onOpenCoverStudio,
            onUploadCover: onUploadCover,
            onSelectionChanged: onSelectionChanged,
            coverThumbnailKey: coverThumbnailKey,
            coverMenuTrigger: coverMenuTrigger,
          ),
          const SizedBox(height: RevericSpacing.x4l),
          _WritingEntries(onSelectionChanged: onSelectionChanged),
          const SizedBox(height: RevericSpacing.x4l),
          // 分层改造（P0）：低频动作统一收在页尾一行（L3 文字链），
          // 包括改目标、文风、按目标排章与一键起稿。
          _ToolRow(
            goal: goal,
            chaptersWithOutline: chapters
                .where(
                  (chapter) =>
                      !chapter.isVolume && chapter.outline.trim().isNotEmpty,
                )
                .length,
            onEditGoal: onEditGoal,
            onEditStyle: onEditStyle,
            onPlanChapters: onPlanChapters,
            onKickoff: novel.description.trim().isEmpty
                ? null
                : () => onContinueWriting(
                      context.t(
                        LocaleKeys.flowKickoffPrompt,
                        namedArgs: {
                          'chapters':
                              '${goal?.chapters ?? defaultTargetChapters}',
                          'per':
                              '${goal?.wordsPerChapter ?? defaultWordsPerChapter}',
                          'batch': '10',
                          'existing':
                              '${chapters.where((chapter) => !chapter.isVolume).length}',
                          'cards': '${characterProfiles.length}',
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Title section: 大标题 + 编辑按钮 + 标签 + 状态徽章
// =============================================================================
class _TitleSection extends ConsumerWidget {
  const _TitleSection({required this.novel, this.onEditNovel});

  final Novel novel;
  final VoidCallback? onEditNovel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final tags = novel.tags;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                novel.title,
                style: typo.display.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: RevericSpacing.md),
            IconButton(
              tooltip: context.t(LocaleKeys.editorEditNovelInfo),
              onPressed: onEditNovel,
              splashRadius: 18,
              icon: RevericIcon(
                RevericIcons.edit_outlined,
                size: 18,
                color: colors.textMuted,
              ),
            ),
            // 草稿不在改编的原著候选里，选不回来，所以只给书架上的小说。
            if (novel.contentKind == contentKindNovel && !novel.draft) ...[
              const SizedBox(width: RevericSpacing.sm),
              RevericButton.secondary(
                onPressed: () => showNovelAdaptationDialog(context, ref, novel),
                icon: RevericIcons.movie_outlined,
                label: context.t(LocaleKeys.libraryActionAdapt),
                size: RevericButtonSize.compact,
              ),
            ],
          ],
        ),
        const SizedBox(height: RevericSpacing.md),
        _StatusBadge(status: novel.status),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: RevericSpacing.sm),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: RevericSpacing.sm,
            runSpacing: RevericSpacing.sm,
            children: [
              for (final tag in tags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.md,
                    vertical: RevericSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(RevericRadius.full),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Text(
                    tag,
                    style: typo.uiTiny.copyWith(color: colors.textSecondary),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final color = _statusColor(colors, status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.md,
        vertical: RevericSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: RevericSpacing.xs),
          Text(
            _statusLabel(context, status),
            style: typo.uiTinySemibold.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Color _statusColor(RevericColors colors, String status) {
    switch (status) {
      case contentStatusFinished:
        return colors.success;
      case contentStatusAbandoned:
        return colors.error;
      case contentStatusArchived:
        return colors.textMuted;
      case contentStatusInProgress:
      default:
        return colors.accentWarm;
    }
  }

  String _statusLabel(BuildContext context, String status) {
    switch (status) {
      case contentStatusFinished:
        return context.t(LocaleKeys.libraryStatusFinished);
      case contentStatusAbandoned:
        return context.t(LocaleKeys.libraryStatusAbandoned);
      case contentStatusArchived:
        return context.t(LocaleKeys.libraryStatusArchived);
      case contentStatusInProgress:
      default:
        return context.t(LocaleKeys.libraryStatusInProgress);
    }
  }
}

// =============================================================================
// Second row: 项目简介 + 创作片段
// =============================================================================
class _SecondRow extends StatelessWidget {
  const _SecondRow({
    required this.novel,
    required this.chapters,
    required this.characterProfiles,
    required this.worldbuildingEntries,
    required this.foreshadowings,
    required this.canOpenCoverStudio,
    required this.onOpenCoverStudio,
    required this.onUploadCover,
    required this.onSelectionChanged,
    required this.coverThumbnailKey,
    required this.coverMenuTrigger,
  });

  final Novel novel;
  final List<Chapter> chapters;
  final List<CharacterProfile> characterProfiles;
  final List<Document> worldbuildingEntries;
  final List<Foreshadowing> foreshadowings;
  final bool canOpenCoverStudio;
  final VoidCallback onOpenCoverStudio;
  final VoidCallback onUploadCover;
  final ValueSetter<WorkspaceSelection> onSelectionChanged;
  final GlobalKey coverThumbnailKey;
  final ValueNotifier<int> coverMenuTrigger;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProjectIntroCard(
          novel: novel,
          chapters: chapters,
          characterProfiles: characterProfiles,
          worldbuildingEntries: worldbuildingEntries,
          foreshadowings: foreshadowings,
          canOpenCoverStudio: canOpenCoverStudio,
          onOpenCoverStudio: onOpenCoverStudio,
          onUploadCover: onUploadCover,
          coverThumbnailKey: coverThumbnailKey,
          coverMenuTrigger: coverMenuTrigger,
        ),
        const SizedBox(height: RevericSpacing.x2l),
        _SnippetsCard(
          foreshadowings: foreshadowings,
          worldbuildingEntries: worldbuildingEntries,
          onSelectionChanged: onSelectionChanged,
        ),
      ],
    );
  }
}

class _ProjectIntroCard extends ConsumerWidget {
  const _ProjectIntroCard({
    required this.novel,
    required this.chapters,
    required this.characterProfiles,
    required this.worldbuildingEntries,
    required this.foreshadowings,
    required this.canOpenCoverStudio,
    required this.onOpenCoverStudio,
    required this.onUploadCover,
    required this.coverThumbnailKey,
    required this.coverMenuTrigger,
  });

  final Novel novel;
  final List<Chapter> chapters;
  final List<CharacterProfile> characterProfiles;
  final List<Document> worldbuildingEntries;
  final List<Foreshadowing> foreshadowings;
  final bool canOpenCoverStudio;
  final VoidCallback onOpenCoverStudio;
  final VoidCallback onUploadCover;
  final GlobalKey coverThumbnailKey;
  final ValueNotifier<int> coverMenuTrigger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final resolvedCoverPath = watchMediaAssetFile(ref, novel.coverAssetId);
    final coverFile = resolvedCoverPath == null
        ? null
        : File(resolvedCoverPath);
    final hasCover = coverFile != null;

    return RevericElevatedCard(
      fallback: colors.surfaceContainerHigh,
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RevericIcon(
                RevericIcons.menu_book_outlined,
                size: 16,
                color: colors.accentWarm,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Text(
                context.t(LocaleKeys.workspaceProjectIntro),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
              const Spacer(),
              if (novel.description.isNotEmpty)
                _CopyButton(text: novel.description),
            ],
          ),
          const SizedBox(height: RevericSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverThumbnail(
                hasCover: hasCover,
                coverFile: coverFile,
                canOpenCoverStudio: canOpenCoverStudio,
                onOpenCoverStudio: onOpenCoverStudio,
                onUploadCover: onUploadCover,
                coverThumbnailKey: coverThumbnailKey,
                coverMenuTrigger: coverMenuTrigger,
              ),
              const SizedBox(width: RevericSpacing.lg),
              Expanded(
                child: SizedBox(
                  height: 120,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      novel.description.isEmpty
                          ? context.t(LocaleKeys.commonNoDescription)
                          : novel.description,
                      style: typo.bodySmall.copyWith(
                        color: colors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.lg),
          RevericElevatedCard(
            fallback: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.lg,
              vertical: RevericSpacing.sm,
            ),
            child: Wrap(
              spacing: RevericSpacing.lg,
              runSpacing: RevericSpacing.xs,
              children: [
                _statText(
                  context,
                  context.t(LocaleKeys.workspaceStatChapters),
                  '${chapters.length}',
                ),
                _statText(
                  context,
                  context.t(LocaleKeys.workspaceStatSettings),
                  '${worldbuildingEntries.length}',
                ),
                _statText(
                  context,
                  context.t(LocaleKeys.workspaceStatCharacters),
                  '${characterProfiles.length}',
                ),
                _statText(
                  context,
                  context.t(LocaleKeys.workspaceStatNotes),
                  '${foreshadowings.length}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statText(BuildContext context, String label, String value) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: typo.uiSmall.copyWith(color: colors.textMuted)),
        const SizedBox(width: RevericSpacing.xs),
        Text(
          value,
          style: typo.uiSmallSemibold.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}

class _CoverThumbnail extends HookWidget {
  const _CoverThumbnail({
    required this.hasCover,
    required this.coverFile,
    required this.canOpenCoverStudio,
    required this.onOpenCoverStudio,
    required this.onUploadCover,
    required this.coverThumbnailKey,
    required this.coverMenuTrigger,
  });

  final bool hasCover;
  final File? coverFile;
  final bool canOpenCoverStudio;
  final VoidCallback onOpenCoverStudio;
  final VoidCallback onUploadCover;
  final GlobalKey coverThumbnailKey;
  final ValueNotifier<int> coverMenuTrigger;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final coverImageProvider = hasCover && coverFile != null
        ? ResizeImage(FileImage(coverFile!), width: _coverThumbnailCacheWidth)
        : null;
    final menuOpen = useRef(false);

    Future<void> openMenu() async {
      if (!context.mounted || menuOpen.value) {
        return;
      }
      final box =
          coverThumbnailKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) {
        return;
      }
      menuOpen.value = true;
      try {
        await showRevericContextMenu(
          context: context,
          position: box.localToGlobal(Offset(0, box.size.height)),
          entries: [
            if (hasCover) ...[
              RevericMenuItem(
                label: context.t(LocaleKeys.workspaceCoverPreview),
                icon: RevericIcons.open_in_full_rounded,
                onTap: () {
                  if (coverFile != null) {
                    _showCoverPreview(context, coverFile!);
                  }
                },
              ),
              RevericMenuItem(
                label: context.t(LocaleKeys.workspaceCoverSaveLocal),
                icon: RevericIcons.download,
                onTap: () {
                  if (coverFile != null) {
                    _saveCoverLocally(context, coverFile!);
                  }
                },
              ),
              const RevericMenuDivider(),
            ],
            RevericMenuItem(
              label: context.t(LocaleKeys.editorOpenCoverStudio),
              icon: RevericIcons.auto_awesome,
              onTap: () {
                if (canOpenCoverStudio) {
                  onOpenCoverStudio();
                } else {
                  showAgentModelSettingsDialog(context);
                }
              },
            ),
            RevericMenuItem(
              label: context.t(LocaleKeys.editorUploadCover),
              icon: RevericIcons.upload_outlined,
              onTap: onUploadCover,
            ),
          ],
        );
      } finally {
        menuOpen.value = false;
      }
    }

    useOnListenableChange(coverMenuTrigger, () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          openMenu();
        }
      });
    });

    return InkWell(
      onTap: openMenu,
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: RevericElevatedCard(
        key: coverThumbnailKey,
        fallback: colors.surface,
        width: 80,
        height: 112,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        clipBehavior: Clip.antiAlias,
        child: coverImageProvider == null
            ? _CoverThumbnailPlaceholder(colors: colors)
            : SizedBox.expand(
                child: Image(
                  image: coverImageProvider,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      _CoverThumbnailPlaceholder(colors: colors),
                ),
              ),
      ),
    );
  }
}

void _showCoverPreview(BuildContext context, File coverFile) {
  final colors = RevericTheme.colorsOf(context);
  final screenSize = MediaQuery.sizeOf(context);

  showDialog<void>(
    context: context,
    barrierColor: colors.textPrimary.withValues(alpha: 0.72),
    builder: (context) {
      return Dialog(
        backgroundColor: colors.surface,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(RevericSpacing.x4l),
        child: SizedBox(
          width: screenSize.width * 0.72,
          height: screenSize.height * 0.78,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  maxScale: 4,
                  child: Center(
                    child: Image.file(
                      coverFile,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          _CoverThumbnailPlaceholder(colors: colors),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: RevericSpacing.sm,
                right: RevericSpacing.sm,
                child: IconButton(
                  tooltip: context.t(LocaleKeys.commonClose),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: RevericIcon(
                    RevericIcons.close_rounded,
                    size: 18,
                    color: colors.textPrimary,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: colors.surface.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _saveCoverLocally(BuildContext context, File coverFile) async {
  final location = await getSaveLocation(
    suggestedName: coverFile.uri.pathSegments.last,
  );
  if (!context.mounted || location == null) {
    return;
  }

  try {
    final savedFile = await coverFile.copy(location.path);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.t(
            LocaleKeys.workspaceCoverSaveSuccess,
            namedArgs: {'file': savedFile.path},
          ),
        ),
      ),
    );
  } catch (error, stackTrace) {
    debugPrintStack(
      label: 'Failed to save novel cover',
      stackTrace: stackTrace,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t(LocaleKeys.workspaceCoverSaveFailed))),
    );
  }
}

class _CoverThumbnailPlaceholder extends StatelessWidget {
  const _CoverThumbnailPlaceholder({required this.colors});

  final RevericColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RevericIcon(
        RevericIcons.image_outlined,
        size: 32,
        color: colors.textMuted,
      ),
    );
  }
}

class _SnippetsCard extends StatelessWidget {
  const _SnippetsCard({
    required this.foreshadowings,
    required this.worldbuildingEntries,
    required this.onSelectionChanged,
  });

  final List<Foreshadowing> foreshadowings;
  final List<Document> worldbuildingEntries;
  final ValueSetter<WorkspaceSelection> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final notes = _buildNotes(context);

    return RevericElevatedCard(
      fallback: colors.surfaceContainerHigh,
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RevericIcon(
                RevericIcons.auto_awesome,
                size: 16,
                color: colors.accentWarm,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Text(
                context.t(LocaleKeys.workspaceCreativeSnippets),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
              const Spacer(),
              InkWell(
                onTap: () => onSelectionChanged(
                  const WorkspaceSelection(
                    section: NovelWorkspaceSection.foreshadowings,
                  ),
                ),
                borderRadius: BorderRadius.circular(RevericRadius.medium),
                child: Padding(
                  padding: const EdgeInsets.all(RevericSpacing.xs),
                  child: Row(
                    children: [
                      Text(
                        context.t(LocaleKeys.workspaceCreativeSnippetsViewMore),
                        style: typo.uiSmall.copyWith(color: colors.accentWarm),
                      ),
                      RevericIcon(
                        RevericIcons.chevron_right,
                        size: 14,
                        color: colors.accentWarm,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.lg),
          if (notes.isEmpty)
            _SnippetEmptyState(
              onTap: () => onSelectionChanged(
                const WorkspaceSelection(
                  section: NovelWorkspaceSection.foreshadowings,
                ),
              ),
            )
          else
            _StickyNotesRow(notes: notes),
        ],
      ),
    );
  }

  List<_SnippetNote> _buildNotes(BuildContext context) {
    final result = <_SnippetNote>[];
    final inspirationLabel = context.t(
      LocaleKeys.workspaceSnippetTagInspiration,
    );
    final settingLabel = context.t(LocaleKeys.workspaceSnippetTagSetting);
    final relationLabel = context.t(LocaleKeys.workspaceSnippetTagRelation);

    for (final foreshadow in foreshadowings) {
      if (result.length >= 3) break;
      final body = foreshadow.setup.isNotEmpty
          ? foreshadow.setup
          : foreshadow.payoff;
      if (body.isEmpty) continue;
      result.add(
        _SnippetNote(
          body: body,
          title: foreshadow.title,
          tag: inspirationLabel,
        ),
      );
    }

    if (result.length < 3) {
      for (final entry in worldbuildingEntries) {
        if (result.length >= 3) break;
        if (entry.content.isEmpty) continue;
        result.add(
          _SnippetNote(
            body: entry.content,
            title: entry.title,
            tag: result.length == 2 ? relationLabel : settingLabel,
          ),
        );
      }
    }

    return result;
  }
}

class _SnippetNote {
  const _SnippetNote({
    required this.body,
    required this.title,
    required this.tag,
  });

  final String body;
  final String title;
  final String tag;
}

class _StickyNotesRow extends StatelessWidget {
  const _StickyNotesRow({required this.notes});

  final List<_SnippetNote> notes;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final palette = <Color>[
      colors.accentAmber.withValues(alpha: 0.18),
      colors.accent.withValues(alpha: 0.12),
      colors.accentWarm.withValues(alpha: 0.16),
    ];
    final tints = <Color>[colors.accentAmber, colors.accent, colors.accentWarm];

    return SizedBox(
      height: 168,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = notes.length.clamp(1, 3);
          final spacing = RevericSpacing.lg;
          final available = constraints.maxWidth;
          final itemWidth = ((available - spacing * (count - 1)) / count).clamp(
            160.0,
            220.0,
          );
          final angles = const [-0.04, 0.02, -0.015];
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                Transform.rotate(
                  angle: angles[i % angles.length],
                  child: SizedBox(
                    width: itemWidth,
                    child: _StickyNoteCard(
                      note: notes[i],
                      background: palette[i % palette.length],
                      accent: tints[i % tints.length],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StickyNoteCard extends StatelessWidget {
  const _StickyNoteCard({
    required this.note,
    required this.background,
    required this.accent,
  });

  final _SnippetNote note;
  final Color background;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        boxShadow: [
          BoxShadow(
            color: colors.textPrimary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Text(
              note.body,
              style: typo.bodySmall.copyWith(
                color: colors.textPrimary,
                height: 1.5,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: RevericSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '— ${note.tag}',
              style: typo.uiTiny.copyWith(
                color: accent,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnippetEmptyState extends StatelessWidget {
  const _SnippetEmptyState({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return RevericElevatedInkWell(
      fallback: colors.surface,
      onTap: onTap,
      height: 140,
      padding: const EdgeInsets.all(RevericSpacing.lg),
      borderRadius: BorderRadius.circular(RevericRadius.large),
      alignment: Alignment.center,
      child: Text(
        context.t(LocaleKeys.workspaceCreativeSnippetsEmpty),
        textAlign: TextAlign.center,
        style: typo.uiSmall.copyWith(color: colors.textMuted),
      ),
    );
  }
}

// =============================================================================
// Writing entries: 4 large cards
// =============================================================================
class _WritingEntries extends StatelessWidget {
  const _WritingEntries({required this.onSelectionChanged});

  final ValueSetter<WorkspaceSelection> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final entries = <_EntrySpec>[
      _EntrySpec(
        icon: RevericIcons.edit_note_outlined,
        title: context.t(LocaleKeys.workspaceWritingMain),
        hint: context.t(LocaleKeys.workspaceWritingMainHint),
        tint: colors.accentAmber,
        section: NovelWorkspaceSection.chapters,
      ),
      _EntrySpec(
        icon: RevericIcons.public_outlined,
        title: context.t(LocaleKeys.workspaceLore),
        hint: context.t(LocaleKeys.workspaceLoreHint),
        tint: colors.accent,
        section: NovelWorkspaceSection.lore,
      ),
      _EntrySpec(
        icon: RevericIcons.auto_stories_outlined,
        title: context.t(LocaleKeys.workspaceWritingOutlinePlot),
        hint: context.t(LocaleKeys.workspaceWritingOutlinePlotHint),
        tint: colors.accentWarm,
        section: NovelWorkspaceSection.outlines,
      ),
      _EntrySpec(
        icon: RevericIcons.people_alt_outlined,
        title: context.t(LocaleKeys.workspaceWritingCharacters),
        hint: context.t(LocaleKeys.workspaceWritingCharactersHint),
        tint: colors.accent,
        section: NovelWorkspaceSection.characters,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t(LocaleKeys.workspaceWritingEntrances),
          style: typo.heading2.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: RevericSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            const minCardWidth = 200.0;
            const spacing = RevericSpacing.lg;
            final totalSpacing = spacing * 3;
            final canFitFourInOneRow =
                constraints.maxWidth >= minCardWidth * 4 + totalSpacing;

            if (canFitFourInOneRow) {
              return Row(
                spacing: spacing,
                children: [
                  for (final entry in entries)
                    Expanded(
                      child: _EntryCard(
                        spec: entry,
                        onTap: () => onSelectionChanged(
                          WorkspaceSelection(section: entry.section),
                        ),
                      ),
                    ),
                ],
              );
            } else {
              final rowSpacing = spacing;
              final colSpacing = spacing;
              final cardWidth = (constraints.maxWidth - rowSpacing) / 2;
              return Column(
                spacing: colSpacing,
                children: [
                  Row(
                    spacing: rowSpacing,
                    children: [
                      for (final entry in entries.take(2))
                        SizedBox(
                          width: cardWidth,
                          child: _EntryCard(
                            spec: entry,
                            onTap: () => onSelectionChanged(
                              WorkspaceSelection(section: entry.section),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Row(
                    spacing: rowSpacing,
                    children: [
                      for (final entry in entries.skip(2))
                        SizedBox(
                          width: cardWidth,
                          child: _EntryCard(
                            spec: entry,
                            onTap: () => onSelectionChanged(
                              WorkspaceSelection(section: entry.section),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            }
          },
        ),
      ],
    );
  }
}

class _EntrySpec {
  const _EntrySpec({
    required this.icon,
    required this.title,
    required this.hint,
    required this.tint,
    required this.section,
  });

  final String icon;
  final String title;
  final String hint;
  final Color tint;
  final NovelWorkspaceSection section;
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.spec, required this.onTap});

  final _EntrySpec spec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.pill),
      child: Container(
        padding: const EdgeInsets.all(RevericSpacing.x2l),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              spec.tint.withValues(alpha: 0.14),
              spec.tint.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(RevericRadius.pill),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(RevericRadius.large),
              ),
              alignment: Alignment.center,
              child: RevericIcon(spec.icon, size: 20, color: spec.tint),
            ),
            const SizedBox(height: RevericSpacing.lg),
            Text(
              spec.title,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.xs),
            Text(
              spec.hint,
              style: typo.uiSmall.copyWith(
                color: colors.textMuted,
                height: 1.5,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: RevericSpacing.lg),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: RevericIcon(
                  RevericIcons.arrow_forward,
                  size: 14,
                  color: spec.tint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Helpers
// =============================================================================
class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return SizedBox(
      width: 24,
      height: 24,
      child: IconButton(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: text));
        },
        icon: RevericIcon(
          RevericIcons.copy_rounded,
          size: 14,
          color: colors.textMuted,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        tooltip: context.t(LocaleKeys.commonCopy),
      ),
    );
  }
}

// =============================================================================
// Next-step guide: 按建设度提示下一步该做什么（微调新增，不改布局）
// 无章节时给出「先搭世界观 → 设定角色 → 规划大纲 → 写第1章」的顺序引导；
// 已有章节则隐藏，交给「继续写作」入口。
// =============================================================================
/// 七站写作进度 + 按状态算出的下一步。
///
/// 之前的「下一步建议」在第一章出现后就返回 null（`return null`），
/// 于是"开始写了"恰恰是引导消失的时刻——这正是复验里"写完两章不知道下一步"的界面成因。
/// 现在改成一条状态链：立项 → 世界观 → 人物 → 大纲 → 章纲 → 正文 → 沉淀 →（定稿），
/// 每一站都由库里真实数据判定，不靠模型自觉。
class _FlowProgressCard extends StatelessWidget {
  const _FlowProgressCard({
    required this.novel,
    required this.characterProfiles,
    required this.worldbuildingEntries,
    required this.outlineEntries,
    required this.chapters,
    required this.foreshadowings,
    required this.goal,
    required this.onSelectionChanged,
    this.onPlanChapters,
  });

  final Novel novel;
  final List<CharacterProfile> characterProfiles;
  final List<Document> worldbuildingEntries;
  final List<OutlineDraft> outlineEntries;
  final List<Chapter> chapters;
  final List<Foreshadowing> foreshadowings;
  final NovelGoal? goal;
  final ValueSetter<WorkspaceSelection> onSelectionChanged;

  /// 「一章都没排」这条缺口需要一个"按目标排章"的动作，仍留在进度卡里；
  /// 其余三个目标类动作已收到页尾工具行。
  final VoidCallback? onPlanChapters;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final stage = _resolveStage();
    final bodyChapters = chapters.where((chapter) => !chapter.isVolume).toList();
    final written = bodyChapters
        .where((chapter) => chapter.wordCount > 0 || chapter.content.trim().isNotEmpty)
        .toList();

    final stageLabels = <String>[
      context.t(LocaleKeys.flowStageIdea),
      context.t(LocaleKeys.flowStageWorld),
      context.t(LocaleKeys.flowStageCharacters),
      context.t(LocaleKeys.flowStageOutline),
      context.t(LocaleKeys.flowStageChapterOutline),
      context.t(LocaleKeys.flowStageWriting),
      context.t(LocaleKeys.flowStageSettle),
    ];

    return RevericElevatedCard(
      fallback: colors.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      gradientColors: (fill, active) => [
        fill,
        colors.accentWarm.withValues(alpha: active ? 0.06 : 0.08),
      ],
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x4l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RevericIcon(
                  RevericIcons.auto_awesome_outlined,
                  size: 18,
                  color: colors.accentWarm,
                ),
                const SizedBox(width: RevericSpacing.sm),
                Text(
                  context.t(LocaleKeys.flowTitle),
                  style: typo.uiSemibold.copyWith(color: colors.accentWarm),
                ),
                const SizedBox(width: RevericSpacing.md),
                Expanded(
                  child: Text(
                    context.t(
                      LocaleKeys.flowCounts,
                      namedArgs: {
                        'world': '${worldbuildingEntries.length}',
                        'characters': '${characterProfiles.length}',
                        'foreshadowings': '${foreshadowings.length}',
                        'chapters': '${written.length}',
                      },
                    ),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RevericSpacing.x2l),
            _GoalRow(
              goal: goal,
              chaptersWithOutline: chapters
                  .where(
                    (chapter) =>
                        !chapter.isVolume && chapter.outline.trim().isNotEmpty,
                  )
                  .length,
            ),
            const SizedBox(height: RevericSpacing.x2l),
            Wrap(
              spacing: RevericSpacing.sm,
              runSpacing: RevericSpacing.xs,
              children: [
                for (var i = 0; i < stageLabels.length; i++)
                  _StagePill(
                    index: i + 1,
                    label: stageLabels[i],
                    done: i < stage,
                    current: i == stage,
                  ),
              ],
            ),
            const SizedBox(height: RevericSpacing.x3l),
            Text(
              stage == -1
                  ? context.t(LocaleKeys.flowNextTitlePublish)
                  : _nextTitle(context, stage, written.length),
              style: typo.heading2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.sm),
            Text(
              stage == -1
                  ? context.t(LocaleKeys.flowNextDescPublish)
                  : _nextDesc(context, stage),
              style: typo.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: RevericSpacing.md),
            // 分层改造（P0）：整页只允许一个黑底主按钮，它属于「继续写作」hero。
            // 这一站的动作降级为文字链（L3：动词 + 箭头），避免一屏两个实心按钮
            // 让作者不知道先点哪个。
            Align(
              alignment: Alignment.centerLeft,
              child: RevericButton.text(
                label:
                    '${stage == -1 ? context.t(LocaleKeys.flowActionPublish) : _nextActionLabel(context, stage)} ›',
                size: RevericButtonSize.compact,
                onPressed: () =>
                    onSelectionChanged(WorkspaceSelection(section: _nextSection(stage))),
              ),
            ),
            const SizedBox(height: RevericSpacing.x3l),
            Container(height: 1, color: colors.borderSubtle),
            const SizedBox(height: RevericSpacing.x2l),
            _buildGapChecklist(context, bodyChapters),
          ],
        ),
      ),
    );
  }

  /// 「还差这些」：把七站里"存在但没填完"的缺口逐条列出来，每条给一个直达入口。
  ///
  /// 七站进度只看"有没有条目"，所以人物卡全空、章纲全缺时进度条照样显示已完成，
  /// 作者写了几章以后打开面板仍然一片空白。这里按真实字段算缺口，并 reused
  /// chapter_cast 判断"人名已经在章纲/正文里出现、但首次出场还没落位"的角色。
  Widget _buildGapChecklist(BuildContext context, List<Chapter> bodyChapters) {
    final rows = <Widget>[];

    void addRow({
      required String label,
      String? actionLabel,
      VoidCallback? onAction,
    }) {
      rows.add(
        _GapRow(
          label: label,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      );
    }

    if (novel.description.trim().isEmpty) {
      addRow(
        label: context.t(LocaleKeys.flowGapDescription),
        actionLabel: context.t(LocaleKeys.flowGapActionDescription),
        onAction: () => onSelectionChanged(
          const WorkspaceSelection(section: NovelWorkspaceSection.novel_description),
        ),
      );
    }

    if (worldbuildingEntries.isEmpty) {
      addRow(
        label: context.t(LocaleKeys.flowGapWorld),
        actionLabel: context.t(LocaleKeys.flowGapActionWorld),
        onAction: () => onSelectionChanged(
          const WorkspaceSelection(section: NovelWorkspaceSection.lore),
        ),
      );
    }

    if (characterProfiles.isEmpty) {
      addRow(
        label: context.t(LocaleKeys.flowGapCharacters),
        actionLabel: context.t(LocaleKeys.flowGapActionCharacters),
        onAction: () => onSelectionChanged(
          const WorkspaceSelection(section: NovelWorkspaceSection.characters),
        ),
      );
    } else {
      final emptyCards = characterProfiles.where((character) =>
          character.identity.trim().isEmpty &&
          character.personality.trim().isEmpty &&
          character.motivation.trim().isEmpty &&
          character.biography.trim().isEmpty).length;
      if (emptyCards > 0) {
        addRow(
          label: context.t(
            LocaleKeys.flowGapCharacterEmpty,
            namedArgs: {'count': '$emptyCards'},
          ),
          actionLabel: context.t(LocaleKeys.flowGapActionCharacters),
          onAction: () => onSelectionChanged(
            const WorkspaceSelection(section: NovelWorkspaceSection.characters),
          ),
        );
      }

      final unplaced = characterProfiles.where((character) {
        if (character.firstAppearChapterId != null &&
            character.firstAppearChapterId!.trim().isNotEmpty) {
          return false;
        }
        final terms = castTermsOf(character);
        return terms.isNotEmpty &&
            firstChapterMatchingTerms(terms: terms, chapters: chapters) !=
                null;
      }).length;
      if (unplaced > 0) {
        addRow(
          label: context.t(
            LocaleKeys.flowGapCharacterUnplaced,
            namedArgs: {'count': '$unplaced'},
          ),
          actionLabel: context.t(LocaleKeys.flowGapActionCharacters),
          onAction: () => onSelectionChanged(
            const WorkspaceSelection(section: NovelWorkspaceSection.characters),
          ),
        );
      }
    }

    if (bodyChapters.isEmpty) {
      addRow(
        label: context.t(LocaleKeys.flowGapChapters),
        actionLabel: onPlanChapters == null
            ? null
            : context.t(LocaleKeys.flowGapActionPlan),
        onAction: onPlanChapters,
      );
    } else {
      final missingOutline = bodyChapters
          .where((chapter) => chapter.outline.trim().isEmpty)
          .toList();
      if (missingOutline.isNotEmpty) {
        addRow(
          label: context.t(
            LocaleKeys.flowGapChapterOutline,
            namedArgs: {'count': '${missingOutline.length}'},
          ),
          actionLabel: context.t(LocaleKeys.flowGapActionOutline),
          onAction: () => onSelectionChanged(
            WorkspaceSelection(
              section: NovelWorkspaceSection.chapters,
              itemId: missingOutline.first.id,
            ),
          ),
        );
      }

      final unsettled = bodyChapters.where((chapter) {
        final written =
            chapter.wordCount > 0 || chapter.content.trim().isNotEmpty;
        final stat = normalizeChapterStat(chapter.stat);
        return written &&
            (stat == chapterStatDraft || stat == chapterStatWriting);
      }).toList();
      if (unsettled.isNotEmpty) {
        addRow(
          label: context.t(
            LocaleKeys.flowGapSettle,
            namedArgs: {'count': '${unsettled.length}'},
          ),
          actionLabel: context.t(LocaleKeys.flowGapActionSettle),
          onAction: () => onSelectionChanged(
            WorkspaceSelection(
              section: NovelWorkspaceSection.chapters,
              itemId: unsettled.first.id,
            ),
          ),
        );
      }
    }

    // 分层改造（P0）：缺口清单默认收起成一行摘要，点开才逐条展开。
    // 之前 5–7 条缺口各带一个按钮常驻展开，一屏十几处可点区域，把主行动淹没了。
    return _GapChecklist(rows: rows);
  }

  /// 返回当前应该做的站序号（0–6）；-1 表示七站都完成。
  int _resolveStage() {
    if (novel.description.trim().isEmpty) return 0;
    if (worldbuildingEntries.isEmpty) return 1;
    if (characterProfiles.isEmpty) return 2;
    if (outlineEntries.isEmpty) return 3;
    final withOutline = chapters
        .where((chapter) => !chapter.isVolume && chapter.outline.trim().isNotEmpty)
        .length;
    if (withOutline == 0) return 4;
    final written = chapters.where(
      (chapter) =>
          !chapter.isVolume &&
          (chapter.wordCount > 0 || chapter.content.trim().isNotEmpty),
    );
    if (written.isEmpty) return 5;
    final unsettled = written.where(
      (chapter) =>
          normalizeChapterStat(chapter.stat) == chapterStatDraft ||
          normalizeChapterStat(chapter.stat) == chapterStatWriting,
    );
    if (unsettled.isNotEmpty) return 6;
    return -1;
  }

  String _nextTitle(BuildContext context, int stage, int writtenCount) {
    switch (stage) {
      case 0:
        return context.t(LocaleKeys.flowNextTitleIdea);
      case 1:
        return context.t(LocaleKeys.flowNextTitleWorld);
      case 2:
        return context.t(LocaleKeys.flowNextTitleCharacters);
      case 3:
        return context.t(LocaleKeys.flowNextTitleOutline);
      case 4:
        return context.t(LocaleKeys.flowNextTitleChapterOutline);
      case 5:
        return context.t(
          LocaleKeys.flowNextTitleWriting,
          namedArgs: {'number': '${writtenCount + 1}'},
        );
      default:
        return context.t(LocaleKeys.flowNextTitleSettle);
    }
  }

  String _nextDesc(BuildContext context, int stage) {
    switch (stage) {
      case 0:
        return context.t(LocaleKeys.flowNextDescIdea);
      case 1:
        return context.t(LocaleKeys.flowNextDescWorld);
      case 2:
        return context.t(LocaleKeys.flowNextDescCharacters);
      case 3:
        return context.t(LocaleKeys.flowNextDescOutline);
      case 4:
        return context.t(LocaleKeys.flowNextDescChapterOutline);
      case 5:
        return context.t(LocaleKeys.flowNextDescWriting);
      default:
        return context.t(LocaleKeys.flowNextDescSettle);
    }
  }

  String _nextActionLabel(BuildContext context, int stage) {
    switch (stage) {
      case 0:
        return context.t(LocaleKeys.flowActionIdea);
      case 1:
        return context.t(LocaleKeys.flowActionWorld);
      case 2:
        return context.t(LocaleKeys.flowActionCharacters);
      case 3:
        return context.t(LocaleKeys.flowActionOutline);
      case 4:
        return context.t(LocaleKeys.flowActionChapterOutline);
      case 5:
        return context.t(LocaleKeys.flowActionWriting);
      default:
        return context.t(LocaleKeys.flowActionSettle);
    }
  }

  NovelWorkspaceSection _nextSection(int stage) {
    switch (stage) {
      case 0:
        return NovelWorkspaceSection.novel_description;
      case 1:
        return NovelWorkspaceSection.lore;
      case 2:
        return NovelWorkspaceSection.characters;
      case 3:
        return NovelWorkspaceSection.outlines;
      case 4:
      case 5:
      case 6:
      default:
        return NovelWorkspaceSection.chapters;
    }
  }
}

/// 页尾工具行：低频动作的固定归属地。
///
/// 分层规则里"每屏只有一个黑底主按钮"，所以改目标、文风、按目标排章、
/// 一键起稿这些"偶尔才用一次"的动作全部降为 L3 文字链，并集中到最后一行，
/// 首屏不再被它们切碎。
class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.goal,
    required this.chaptersWithOutline,
    required this.onEditGoal,
    required this.onEditStyle,
    required this.onPlanChapters,
    required this.onKickoff,
  });

  final NovelGoal? goal;
  final int chaptersWithOutline;
  final VoidCallback? onEditGoal;
  final VoidCallback? onEditStyle;
  final VoidCallback? onPlanChapters;
  final VoidCallback? onKickoff;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final current = goal;
    final canPlan = current != null &&
        current.isUsable &&
        chaptersWithOutline < current.chapters &&
        onPlanChapters != null;

    final links = <Widget>[
      if (onEditGoal != null)
        RevericButton.text(
          label: context.t(LocaleKeys.flowToolsGoal),
          size: RevericButtonSize.compact,
          onPressed: onEditGoal,
        ),
      if (onEditStyle != null)
        RevericButton.text(
          label: context.t(LocaleKeys.flowToolsStyle),
          size: RevericButtonSize.compact,
          onPressed: onEditStyle,
        ),
      if (canPlan)
        RevericButton.text(
          label: context.t(
            LocaleKeys.flowToolsPlan,
            namedArgs: {'chapters': '${current.chapters}'},
          ),
          size: RevericButtonSize.compact,
          onPressed: onPlanChapters,
        ),
      if (onKickoff != null)
        RevericButton.text(
          label: context.t(LocaleKeys.flowToolsKickoff),
          size: RevericButtonSize.compact,
          onPressed: onKickoff,
        ),
    ];

    if (links.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.only(top: RevericSpacing.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Wrap(
        spacing: RevericSpacing.lg,
        runSpacing: RevericSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            context.t(LocaleKeys.flowToolsLabel),
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
          ...links,
        ],
      ),
    );
  }
}

/// 全书目标行：目标章数 / 每章字数 / 已排到第几章。
///
/// 没有这一行时，"要写多少章、每章多少字"只存在于作者脑子里，AI 无从控制节奏，
/// 进度卡也就只能说"该写下一章"，说不出"还差 114 章"。
/// 分层改造（P0）后这一行只**读**目标，不再挂三个动作按钮——改目标、文风、
/// 排章统一在页尾工具行，让进度卡只剩"读到哪了"这一件事。
class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.goal,
    required this.chaptersWithOutline,
  });

  final NovelGoal? goal;
  final int chaptersWithOutline;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final current = goal;

    final text = current == null || !current.isUsable
        ? context.t(LocaleKeys.flowGoalUnset)
        : context.t(
            LocaleKeys.flowGoal,
            namedArgs: {
              'chapters': '${current.chapters}',
              'per': '${current.wordsPerChapter}',
              'total': (current.totalWords / 10000).toStringAsFixed(1),
              'done': '$chaptersWithOutline',
            },
          );

    // 分层改造（P0）：目标只在这里"读一次"，改目标/文风/排章三个动作
    // 统一收在页尾工具行，不在进度卡里和主行动抢注意力。
    return Row(
      children: [
        RevericIcon(RevericIcons.outlined_flag, size: 14, color: colors.textMuted),
        const SizedBox(width: RevericSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: typo.uiSmall.copyWith(color: colors.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 一站的药丸：已完成（勾 + 实心）、当前（编号 + 强调色）、未开始（灰）。
class _StagePill extends StatelessWidget {
  const _StagePill({
    required this.index,
    required this.label,
    required this.done,
    required this.current,
  });

  final int index;
  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final accent = current
        ? colors.accentWarm
        : done
        ? colors.additionBorder
        : colors.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: RevericSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: current ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(RevericRadius.full),
        border: Border.all(color: accent.withValues(alpha: current ? 0.4 : 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done)
            RevericIcon(RevericIcons.check_circle, size: 12, color: accent)
          else
            Text(
              '$index',
              style: typo.uiSmall.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(width: RevericSpacing.xs),
          Text(
            label,
            style: typo.uiSmall.copyWith(
              color: current ? colors.textPrimary : accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// 缺口清单的折叠外壳：收起时只有一行「还差 N 项 ›」，展开才逐条列出。
///
/// 收起状态**不做持久化**——每次进概览页都从收起开始，首屏永远清爽；
/// 展开是为了"我现在就想知道差哪几项"，不是为了常驻。
class _GapChecklist extends StatefulWidget {
  const _GapChecklist({required this.rows});

  final List<Widget> rows;

  @override
  State<_GapChecklist> createState() => _GapChecklistState();
}

class _GapChecklistState extends State<_GapChecklist> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final count = widget.rows.length;

    if (count == 0) {
      return Row(
        children: [
          RevericIcon(
            RevericIcons.check_circle,
            size: 14,
            color: colors.additionBorder,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              context.t(LocaleKeys.flowGapReady),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(RevericRadius.small),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: RevericSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RevericIcon(
                  RevericIcons.error_outline,
                  size: 14,
                  color: colors.accentWarm,
                ),
                const SizedBox(width: RevericSpacing.sm),
                Text(
                  context.t(
                    LocaleKeys.flowGapCollapsed,
                    namedArgs: {'count': '$count'},
                  ),
                  style: typo.uiSmall.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(width: RevericSpacing.xs),
                RevericIcon(
                  _expanded
                      ? RevericIcons.expand_less_rounded
                      : RevericIcons.chevron_right,
                  size: 16,
                  color: colors.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: RevericSpacing.xs),
          ...widget.rows,
        ],
      ],
    );
  }
}

/// 「还差这些」里的一行：一句缺口说明 + 一个直达动作。
class _GapRow extends StatelessWidget {
  const _GapRow({
    required this.label,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: colors.accentWarm,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: typo.uiSmall.copyWith(color: colors.textSecondary),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.sm),
                minimumSize: const Size(0, 26),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: typo.uiSmall.copyWith(color: colors.accentWarm),
              ),
            ),
        ],
      ),
    );
  }
}