// 职责: 授权与商业版本页 — 展示免费版 / 标准版 / 专业版三档权益与价格、
//   当前授权状态、授权码激活入口，右侧常驻「购买与咨询」板块（二维码 + 邮件 + 反馈）。
// 关联文件:
//   lib/shared/models/license.dart
//   lib/shared/services/license_service.dart
//   lib/desktop/pages/license_page.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/widgets/support/customer_service_feedback_dialog.dart
//   assets/images/customer_service_qr.jpg
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/settings.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/app_config.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/components/reveric_text_field.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/license.dart';
import '../../../shared/services/license_service.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/support/customer_service_feedback_dialog.dart';

/// 官方客服二维码资源路径。
const String _customerServiceQrAsset = 'assets/images/customer_service_qr.jpg';

/// 宽屏下三档卡片的统一高度，保证三个购买按钮落在同一条水平线上。
const double _planCardHeight = 356;

/// 三档商业方案页：左列方案与激活，右列购买与咨询。
class LicensePricingView extends StatefulWidget {
  const LicensePricingView({super.key});

  @override
  State<LicensePricingView> createState() => _LicensePricingViewState();
}

class _LicensePricingViewState extends State<LicensePricingView> {
  final TextEditingController _codeController = TextEditingController();
  LicenseState _state = const LicenseState.free();
  bool _loading = true;
  bool _activating = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    var state = await LicenseService.load();
    if (state.isActivated && state.needsCheckIn) {
      // token 到期时联网刷新；失败时保留本地状态走离线宽限。
      state = await LicenseService.refreshIfNeeded();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _state = state;
      _loading = false;
    });
  }

  Future<void> _activate() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _activating) {
      return;
    }
    setState(() => _activating = true);
    final result = await LicenseService.activate(code);
    if (!mounted) {
      return;
    }
    setState(() => _activating = false);
    final messenger = ScaffoldMessenger.of(context);
    if (result.isSuccess) {
      _codeController.clear();
      await _reload();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t(LocaleKeys.settingsLicenseActivateSuccess)),
        ),
      );
    } else {
      final messageKey = result.message;
      final text = messageKey == null
          ? context.t(LocaleKeys.settingsLicenseActivateFailed)
          : context.t(
              messageKey,
              namedArgs: <String, String>{
                'current': '${result.state?.features['max_activations'] ?? ''}',
                'message': '',
              },
            );
      messenger.showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _deactivate() async {
    if (_activating) {
      return;
    }
    setState(() => _activating = true);
    await LicenseService.deactivateCurrentDevice();
    if (!mounted) {
      return;
    }
    setState(() => _activating = false);
    final messenger = ScaffoldMessenger.of(context);
    await _reload();
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.t(LocaleKeys.settingsLicenseDeactivateDone)),
      ),
    );
  }

  /// 购买入口不再离开应用，统一引导到客服二维码，避免指向无效的外链。
  Future<void> _showPurchaseDialog() {
    return showRevericDialog<void>(
      context: context,
      builder: (_) => RevericDialog(
        title: context.t(LocaleKeys.settingsLicensePurchaseTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _QrImage(size: 200),
            const SizedBox(height: RevericSpacing.x2l),
            Text(
              context.t(LocaleKeys.settingsLicensePurchaseBody),
              style: RevericTheme.typographyOf(
                context,
              ).ui.copyWith(color: RevericTheme.colorsOf(context).textSecondary),
            ),
            const SizedBox(height: RevericSpacing.lg),
            _ContactSteps(),
            const SizedBox(height: RevericSpacing.x2l),
            _EmailRow(onCopy: _copyEmail),
          ],
        ),
        actions: [
          RevericButton.secondary(
            label: context.t(LocaleKeys.commonClose),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _copyEmail() async {
    await Clipboard.setData(const ClipboardData(text: revericFeedbackEmail));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t(LocaleKeys.commonCopied))),
    );
  }

  String _tierLabel(BuildContext context) {
    return switch (_state.tier) {
      LicenseTier.free => context.t(LocaleKeys.settingsLicenseTierFree),
      LicenseTier.standard => context.t(LocaleKeys.settingsLicenseTierStandard),
      LicenseTier.pro => context.t(LocaleKeys.settingsLicenseTierPro),
    };
  }

  String? _expiryText(BuildContext context) {
    if (!_state.isActivated) {
      return null;
    }
    final expires = _state.expiresAt;
    if (expires == null) {
      return context.t(LocaleKeys.settingsLicensePermanent);
    }
    final local = expires.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    return context.t(
      LocaleKeys.settingsLicenseExpiresAt,
      namedArgs: <String, String>{'date': date},
    );
  }

  String _deviceLabel() {
    final id = _state.deviceId;
    if (id == null || id.isEmpty) {
      return '';
    }
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t(LocaleKeys.settingsLicensePricingTitle),
          style: typo.heading2.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: RevericSpacing.xs),
        Text(
          context.t(LocaleKeys.settingsLicensePricingSubtitle),
          style: typo.ui.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: RevericSpacing.x2l),
        _StatusBar(
          loading: _loading,
          title: _loading
              ? context.t(LocaleKeys.settingsLicenseLoading)
              : context.t(
                  LocaleKeys.settingsLicenseCurrentTier,
                  namedArgs: <String, String>{'tier': _tierLabel(context)},
                ),
          expiryText: _expiryText(context),
          deviceText: _state.isActivated
              ? context.t(
                  LocaleKeys.settingsLicenseDeviceBound,
                  namedArgs: <String, String>{'device': _deviceLabel()},
                )
              : null,
          onDeactivate: _state.isActivated && !_activating ? _deactivate : null,
        ),
        const SizedBox(height: RevericSpacing.x2l),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final cards = _buildCards(context, fillHeight: wide);
            if (wide) {
              return SizedBox(
                height: _planCardHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: RevericSpacing.lg),
                      Expanded(child: cards[i]),
                    ],
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: RevericSpacing.md),
                  cards[i],
                ],
              ],
            );
          },
        ),
        const SizedBox(height: RevericSpacing.x2l),
        _ActivateCard(
          controller: _codeController,
          activating: _activating,
          onActivate: _activate,
        ),
      ],
    );

    final side = _ContactCard(onCopyEmail: _copyEmail);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1040;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(RevericSpacing.x4l),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: main),
                    const SizedBox(width: RevericSpacing.x4l),
                    SizedBox(width: 296, child: side),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    main,
                    const SizedBox(height: RevericSpacing.x2l),
                    side,
                  ],
                ),
        );
      },
    );
  }

  List<Widget> _buildCards(BuildContext context, {required bool fillHeight}) {
    final currentLabel = context.t(LocaleKeys.settingsLicenseCurrentBadge);
    return [
      _PlanCard(
        title: context.t(LocaleKeys.settingsLicenseTierFree),
        tagline: context.t(LocaleKeys.settingsLicenseFreeTagline),
        price: context.t(LocaleKeys.settingsLicenseFreePrice),
        features: context.t(LocaleKeys.settingsLicenseFreeFeatures),
        isCurrent: _state.tier == LicenseTier.free,
        actionLabel: _state.tier == LicenseTier.free
            ? currentLabel
            : context.t(LocaleKeys.settingsLicenseFreeCta),
        onPressed: null,
        fillHeight: fillHeight,
      ),
      _PlanCard(
        title: context.t(LocaleKeys.settingsLicenseTierStandard),
        tagline: context.t(LocaleKeys.settingsLicenseStandardTagline),
        price: context.t(LocaleKeys.settingsLicenseStandardPrice),
        features: context.t(LocaleKeys.settingsLicenseStandardFeatures),
        isCurrent: _state.tier == LicenseTier.standard,
        actionLabel: _state.tier == LicenseTier.standard
            ? currentLabel
            : context.t(LocaleKeys.settingsLicenseBuyStandard),
        onPressed: _state.tier == LicenseTier.standard
            ? null
            : _showPurchaseDialog,
        highlighted: true,
        fillHeight: fillHeight,
      ),
      _PlanCard(
        title: context.t(LocaleKeys.settingsLicenseTierPro),
        tagline: context.t(LocaleKeys.settingsLicenseProTagline),
        price: context.t(LocaleKeys.settingsLicenseProPrice),
        features: context.t(LocaleKeys.settingsLicenseProFeatures),
        isCurrent: _state.tier == LicenseTier.pro,
        actionLabel: _state.tier == LicenseTier.pro
            ? currentLabel
            : context.t(LocaleKeys.settingsLicenseBuyPro),
        onPressed: _state.tier == LicenseTier.pro ? null : _showPurchaseDialog,
        fillHeight: fillHeight,
      ),
    ];
  }
}

/// 顶部当前授权状态条：档位、到期时间、绑定设备与解绑入口。
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.loading,
    required this.title,
    required this.expiryText,
    required this.deviceText,
    required this.onDeactivate,
  });

  final bool loading;
  final String title;
  final String? expiryText;
  final String? deviceText;
  final VoidCallback? onDeactivate;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x3l,
        vertical: RevericSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: [
          RevericIcon(
            RevericIcons.crown,
            size: 16,
            color: colors.accent,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: typo.uiSemibold.copyWith(
                    color: loading ? colors.textSecondary : colors.textPrimary,
                  ),
                ),
                if (deviceText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    deviceText!,
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (expiryText != null)
            Text(
              expiryText!,
              style: typo.uiSmall.copyWith(color: colors.textSecondary),
            ),
          if (onDeactivate != null) ...[
            const SizedBox(width: RevericSpacing.sm),
            RevericButton.text(
              label: context.t(LocaleKeys.settingsLicenseDeactivate),
              onPressed: onDeactivate,
              size: RevericButtonSize.compact,
            ),
          ],
        ],
      ),
    );
  }
}

/// 单个档位卡片：名称 + 价格 + 一句定位 + 权益列表 + 行动按钮。
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.tagline,
    required this.price,
    required this.features,
    required this.actionLabel,
    required this.isCurrent,
    this.onPressed,
    this.highlighted = false,
    this.fillHeight = false,
  });

  final String title;
  final String tagline;
  final String price;
  final String features;
  final String actionLabel;
  final bool isCurrent;
  final bool highlighted;
  final VoidCallback? onPressed;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final featureLines = features
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final borderColor = highlighted ? colors.accent : colors.borderSubtle;
    final actionButton = onPressed == null
        ? RevericButton.secondary(label: actionLabel, onPressed: null)
        : highlighted
        ? RevericButton.primary(label: actionLabel, onPressed: onPressed)
        : RevericButton.secondary(label: actionLabel, onPressed: onPressed);
    final featureList = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in featureLines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: RevericSpacing.sm),
                Expanded(
                  child: Text(
                    line,
                    style: typo.ui.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(RevericSpacing.x3l),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.card),
        border: Border.all(
          color: borderColor,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
              ),
              if (isCurrent)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RevericSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(RevericRadius.small),
                    ),
                    child: Text(
                      context.t(LocaleKeys.settingsLicenseCurrentBadge),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typo.uiSmall.copyWith(color: colors.onAccent),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: RevericSpacing.md),
          Text(
            price,
            style: typo.display.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            tagline,
            style: typo.uiSmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: RevericSpacing.x2l),
          if (fillHeight)
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: featureList,
              ),
            )
          else
            featureList,
          const SizedBox(height: RevericSpacing.lg),
          SizedBox(width: double.infinity, child: actionButton),
        ],
      ),
    );
  }
}

/// 授权码激活区：独立卡片，和方案卡片保持同一视觉层级。
class _ActivateCard extends StatelessWidget {
  const _ActivateCard({
    required this.controller,
    required this.activating,
    required this.onActivate,
  });

  final TextEditingController controller;
  final bool activating;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RevericSpacing.x3l),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.card),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(LocaleKeys.settingsLicenseActivateTitle),
            style: typo.uiSemibold.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            context.t(LocaleKeys.settingsLicenseDescription),
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: RevericSpacing.lg),
          Row(
            children: [
              Expanded(
                child: RevericTextField(
                  controller: controller,
                  hintText: context.t(LocaleKeys.settingsLicenseCodeHint),
                  onSubmitted: (_) => onActivate(),
                ),
              ),
              const SizedBox(width: RevericSpacing.lg),
              RevericButton.primary(
                label: context.t(LocaleKeys.settingsLicenseActivate),
                loading: activating,
                onPressed: onActivate,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 右列购买与咨询板块：客服二维码 + 购买步骤 + 邮件与反馈入口。
class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.onCopyEmail});

  final VoidCallback onCopyEmail;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.all(RevericSpacing.x3l),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.card),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RevericIcon(
                RevericIcons.crown,
                size: 16,
                color: colors.accent,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  context.t(LocaleKeys.settingsLicenseContactTitle),
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.lg),
          _QrImage(size: 216),
          const SizedBox(height: RevericSpacing.lg),
          Text(
            context.t(LocaleKeys.settingsLicenseContactHint),
            style: typo.uiSmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: RevericSpacing.x2l),
          _ContactSteps(),
          const SizedBox(height: RevericSpacing.x2l),
          Container(height: 1, color: colors.borderSubtle),
          const SizedBox(height: RevericSpacing.lg),
          _EmailRow(onCopy: onCopyEmail),
          const SizedBox(height: RevericSpacing.lg),
          RevericButton.secondary(
            label: context.t(LocaleKeys.homeNavCustomerService),
            icon: RevericIcons.chat_rounded,
            onPressed: () =>
                showCustomerServiceFeedbackDialog(context: context),
          ),
        ],
      ),
    );
  }
}

/// 二维码图片：浅色描边卡内居中，避免直接压在底色上显得脏。
class _QrImage extends StatelessWidget {
  const _QrImage({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.all(RevericSpacing.sm),
        decoration: BoxDecoration(
          color: colors.canvas,
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(RevericRadius.small),
          child: Image.asset(
            _customerServiceQrAsset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

/// 购买三步说明，购买弹窗与右侧板块共用。
class _ContactSteps extends StatelessWidget {
  const _ContactSteps();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final steps = [
      context.t(LocaleKeys.settingsLicenseStepBuy),
      context.t(LocaleKeys.settingsLicenseStepPay),
      context.t(LocaleKeys.settingsLicenseStepCode),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: RevericSpacing.xxs),
            child: Text(
              step,
              style: typo.uiSmall.copyWith(color: colors.textSecondary),
            ),
          ),
      ],
    );
  }
}

/// 邮件咨询行：地址常显 + 复制按钮。
class _EmailRow extends StatelessWidget {
  const _EmailRow({required this.onCopy});

  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      children: [
        RevericIcon(
          RevericIcons.envelope,
          size: RevericSizes.buttonIconSize,
          color: colors.textMuted,
        ),
        const SizedBox(width: RevericSpacing.sm),
        Expanded(
          child: Text(
            revericFeedbackEmail,
            style: typo.uiSmall.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        RevericIconButton(
          icon: RevericIcons.copy,
          tooltip: context.t(LocaleKeys.commonCopy),
          onPressed: onCopy,
        ),
      ],
    );
  }
}
