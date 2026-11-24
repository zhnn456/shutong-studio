// 职责: 快速开书前收集故事想法，并提供共用的开书提示词拼接。
// 关联文件:
//   lib/desktop/pages/home.dart
//   lib/mobile/pages/library_page.dart
//   lib/mobile/pages/novel_create_page.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/library.json
//   assets/translations/zh-CN/library.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../components/reveric_text_field.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';

/// 桌面弹窗宽度，对齐 `agent_skill_import_dialog` 等既有对话框。
const double _dialogMaxWidth = 480;

String buildQuickStartKickoffPrompt(String idea) =>
    '我想基于下面的想法开始一本新书。请使用「创作向导」技能，严格按它定义的交付标准执行：\n'
    '1. 先只问 3 轮硬决策（方向、篇幅与分卷、不可逆结构），我已经说明的信息不要重复问；\n'
    '2. 然后一次性交付 L2 骨架：世界观 5 条、核心角色 6–8 张完整卡、分卷大纲、'
    '每一卷每一章的标题与梗概（60–100 字），按卷分批生成；\n'
    '3. 生成后按骨架自检 5 条自查（角色引用可查、伏笔能配对、卷章数对齐、核心角色登场、能力上限不被无代价突破），不过就回炉补；\n'
    '4. 不要只交写作规则和元数据，也不要写完就收尾——L2 骨架缺一段都算没完成。\n\n'
    '我的故事想法：\n$idea';

Future<String?> showQuickStartIdea(
  BuildContext context, {
  required bool mobile,
}) {
  final colors = RevericTheme.colorsOf(context);
  if (mobile) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      // sheet 自带标题头与关闭按钮，不再叠加框架 drag handle。
      showDragHandle: false,
      backgroundColor: colors.surface,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            ),
            child: const SingleChildScrollView(child: _IdeaForm(mobile: true)),
          ),
        ),
      ),
    );
  }
  // 确认会创建作品并启动 AI，使用独立输入弹窗承载这次提交。
  return showDialog<String>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _dialogMaxWidth),
        child: const SingleChildScrollView(child: _IdeaForm(mobile: false)),
      ),
    ),
  );
}

class _IdeaForm extends HookWidget {
  const _IdeaForm({required this.mobile});

  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final controller = useTextEditingController();
    final submitted = useRef(false);
    final canSubmit = useListenableSelector(
      controller,
      () => controller.text.trim().isNotEmpty,
    );

    void close() => Navigator.of(context).maybePop();

    void submit() {
      final idea = controller.text.trim();
      if (idea.isEmpty || submitted.value) {
        return;
      }
      submitted.value = true;
      Navigator.of(context).pop(idea);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PromptDialogHeader(
          title: context.t(LocaleKeys.libraryQuickStart),
          subtitle: context.t(LocaleKeys.libraryQuickStartIdeaHelp),
          onClose: close,
        ),
        Divider(
          height: RevericSizes.dividerThickness,
          color: colors.borderSubtle,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.x3l,
            RevericSpacing.x3l,
            RevericSpacing.x3l,
            RevericSpacing.x2l,
          ),
          child: RevericTextField(
            controller: controller,
            autofocus: true,
            multiline: true,
            minLines: 4,
            maxLines: 6,
            textInputAction: TextInputAction.newline,
            hintText: context.t(LocaleKeys.libraryQuickStartIdeaHint),
          ),
        ),
        Divider(
          height: RevericSizes.dividerThickness,
          color: colors.borderSubtle,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            RevericSpacing.x3l,
            RevericSpacing.lg,
            RevericSpacing.x3l,
            // 移动端底部留出 home indicator 的空间。
            mobile ? RevericSpacing.x5l : RevericSpacing.x3l,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: close,
                child: Text(context.t(LocaleKeys.commonCancel)),
              ),
              const SizedBox(width: RevericSpacing.sm),
              FilledButton(
                onPressed: canSubmit ? submit : null,
                child: Text(context.t(LocaleKeys.libraryQuickStartConfirm)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 输入提示后启动 AI 的弹窗头部，快速开书与剧本导入共用。
class PromptDialogHeader extends StatelessWidget {
  const PromptDialogHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onClose,
    this.icon = RevericIcons.auto_awesome,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x3l,
        RevericSpacing.x3l,
        RevericSpacing.x3l,
        RevericSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(RevericRadius.large),
            ),
            child: RevericIcon(icon, size: 18, color: colors.accent),
          ),
          const SizedBox(width: RevericSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: RevericSpacing.sm),
          IconButton(
            onPressed: onClose,
            icon: RevericIcon(
              RevericIcons.close,
              size: 16,
              color: colors.textMuted,
            ),
            iconSize: RevericSizes.iconButtonSize,
            constraints: const BoxConstraints(
              minWidth: RevericSizes.iconButtonSize,
              minHeight: RevericSizes.iconButtonSize,
            ),
            padding: EdgeInsets.zero,
            splashRadius: RevericSizes.iconButtonSize / 2,
          ),
        ],
      ),
    );
  }
}
