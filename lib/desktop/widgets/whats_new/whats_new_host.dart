// 职责: 版本变化后首次进入首页时，在右下角浮出一张「本次更新」卡片，关掉即记住已读。
// 关联文件:
//   lib/shared/services/whats_new_service.dart
//   assets/updates/changelog.json
//   lib/main.dart（在首页外挂载一层）
//   assets/translations/{zh-CN,en}/common.json + lib/shared/localization/locale_keys.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/components/reveric_button.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/services/whats_new_service.dart';
import '../../../shared/theme/theme.dart';

/// 把更新浮窗叠在首页之上；没有待展示内容时不渲染任何额外层。
class WhatsNewHost extends StatefulWidget {
  const WhatsNewHost({super.key, required this.child});

  final Widget child;

  @override
  State<WhatsNewHost> createState() => _WhatsNewHostState();
}

class _WhatsNewHostState extends State<WhatsNewHost> {
  WhatsNewRelease? _release;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final release = await const WhatsNewService().pendingRelease();
    if (!mounted || release == null) return;
    setState(() => _release = release);
    // 等首页首帧铺完再滑入，避免和首页自身的入场动画抢视觉焦点。
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    setState(() => _visible = true);
  }

  Future<void> _dismiss() async {
    if (!_visible) return;
    setState(() => _visible = false);
    await const WhatsNewService().markSeen();
    if (!mounted) return;
    // 等淡出动画结束再移除，避免层级突然塌陷。
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    setState(() => _release = null);
  }

  @override
  Widget build(BuildContext context) {
    final release = _release;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (release != null)
          Positioned(
            right: RevericSpacing.x4l,
            bottom: RevericSpacing.x4l,
            child: IgnorePointer(
              ignoring: !_visible,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                offset: _visible ? Offset.zero : const Offset(0, 0.14),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 240),
                  opacity: _visible ? 1 : 0,
                  child: _WhatsNewCard(
                    release: release,
                    onDismiss: _dismiss,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WhatsNewCard extends StatelessWidget {
  const _WhatsNewCard({required this.release, required this.onDismiss});

  final WhatsNewRelease release;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final languageCode = Localizations.localeOf(context).languageCode;
    final availableWidth = MediaQuery.sizeOf(context).width;
    final width = math.min(384.0, math.max(280.0, availableWidth - RevericSpacing.x6l));

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x3l,
        RevericSpacing.x2l,
        RevericSpacing.x2l,
        RevericSpacing.x2l,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 7),
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      release.title(languageCode),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      release.date.isEmpty
                          ? 'v${release.version}'
                          : 'v${release.version} · ${release.date}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: RevericSpacing.xs),
              _CloseButton(onPressed: onDismiss),
            ],
          ),
          const SizedBox(height: RevericSpacing.x2l),
          for (final item in release.items)
            Padding(
              padding: const EdgeInsets.only(bottom: RevericSpacing.md),
              child: _BulletLine(text: item[languageCode] ?? item['zh'] ?? ''),
            ),
          const SizedBox(height: RevericSpacing.xxs),
          Align(
            alignment: Alignment.centerRight,
            child: RevericButton.primary(
              label: context.t(LocaleKeys.commonWhatsNewGotIt),
              onPressed: onDismiss,
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.check,
            size: 13,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: RevericSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Semantics(
      button: true,
      label: context.t(LocaleKeys.commonClose),
      child: InkResponse(
        onTap: onPressed,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.xxs),
          child: Icon(
            Icons.close,
            size: 15,
            color: colors.textMuted,
          ),
        ),
      ),
    );
  }
}
