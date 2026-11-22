// 职责: 章节编辑页的「本章出场」条 — 实时扫描章纲+正文，反查人物卡
// 关联文件:
//   lib/shared/services/chapter_cast.dart
//   lib/desktop/widgets/workspace/chapter_editor.dart
//   lib/shared/components/reveric_placeholder.dart
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/workspace.json
// 遵循的 Rules: .agents/rules/design-system.md, .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../../shared/components/reveric_placeholder.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/character_profile.dart';
import '../../../shared/services/chapter_cast.dart';
import '../../../shared/theme/reveric_icons.dart';
import '../../../shared/theme/theme.dart';

/// 在章纲与正文之间显示「本章出现谁」，让人物卡与正在写的内容即时对上。
///
/// 只做展示，不写库：人物条出现的前提是作者已经在章纲/正文里写下名字，
/// 并把这个人建成了人物卡。空态里说清这两步，比一个「暂无」有用。
class ChapterCastStrip extends StatelessWidget {
  const ChapterCastStrip({
    super.key,
    required this.outlineController,
    required this.contentController,
    required this.characters,
  });

  final TextEditingController outlineController;
  final TextEditingController contentController;
  final List<CharacterProfile> characters;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return ListenableBuilder(
      listenable: Listenable.merge([outlineController, contentController]),
      builder: (context, _) {
        final outline = outlineController.text;
        final content = contentController.text;
        final hits = scanTextCast(
          outline: outline,
          content: content,
          characters: characters,
        );
        final outlineEmpty = outline.trim().isEmpty;

        if (characters.isEmpty) {
          return RevericPlaceholder.empty(
            icon: RevericIcons.groups_rounded,
            title: context.t(LocaleKeys.workspaceChapterCastNoCharacters),
            description: context.t(
              LocaleKeys.workspaceChapterCastNoCharactersDescription,
            ),
            compact: true,
          );
        }

        if (hits.isEmpty) {
          return RevericPlaceholder.empty(
            icon: RevericIcons.groups_rounded,
            title: context.t(LocaleKeys.workspaceChapterCastEmpty),
            description: outlineEmpty
                ? context.t(LocaleKeys.workspaceChapterCastEmptyNoOutline)
                : context.t(LocaleKeys.workspaceChapterCastEmptyHint),
            compact: true,
          );
        }

        final bodyCount = hits.where((hit) => hit.appearsInBody).length;

        return Container(
          margin: const EdgeInsets.only(bottom: RevericSpacing.md),
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(RevericRadius.x2l),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  RevericIcon(
                    RevericIcons.groups_rounded,
                    size: 14,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: RevericSpacing.xs),
                  Text(
                    context.t(LocaleKeys.workspaceChapterCastTitle),
                    style: typo.uiSmallSemibold.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  Text(
                    '${context.t(LocaleKeys.workspaceChapterCastBody)} $bodyCount'
                    ' · ${context.t(LocaleKeys.workspaceChapterCastOutline)} '
                    '${hits.length}',
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                  const Spacer(),
                  if (content.trim().isEmpty && !outlineEmpty)
                    Text(
                      context.t(LocaleKeys.workspaceChapterCastOutlineOnly),
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                ],
              ),
              const SizedBox(height: RevericSpacing.xs),
              Wrap(
                spacing: RevericSpacing.xs,
                runSpacing: RevericSpacing.xxs,
                children: [
                  for (final hit in hits)
                    Tooltip(
                      message: [
                        if (hit.contentMentions > 0)
                          '${context.t(LocaleKeys.workspaceChapterCastBody)} '
                              '${hit.contentMentions}',
                        if (hit.outlineMentions > 0)
                          '${context.t(LocaleKeys.workspaceChapterCastOutline)} '
                              '${hit.outlineMentions}',
                        if (hit.terms.isNotEmpty) hit.terms.join(' / '),
                      ].join(' · '),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: RevericSpacing.sm,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: hit.appearsInBody
                              ? colors.selected
                              : colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(RevericRadius.x2l),
                        ),
                        child: Text(
                          hit.characterName,
                          style: typo.uiSmall.copyWith(
                            color: hit.appearsInBody
                                ? colors.textPrimary
                                : colors.textMuted,
                          ),
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
