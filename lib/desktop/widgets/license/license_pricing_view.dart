// 职责: 授权与商业版本页 — 展示免费版 / 标准版 / 专业版三档权益与价格、
//   当前授权状态、授权码激活入口与购买入口。被左侧栏「升级授权」一级入口
//   与设置页「授权」分区共用。
// 关联文件:
//   lib/shared/models/license.dart
//   lib/shared/services/license_service.dart
//   lib/desktop/pages/license_page.dart
//   lib/desktop/widgets/settings/settings_license_section.dart
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/settings.json
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/license.dart';
import '../../../shared/services/license_service.dart';
import '../../../shared/theme/theme.dart';

/// 三档商业方案页。宽屏三列横排，窄屏纵向堆叠，卡片等高。
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

  Future<void> _openPurchase() async {
    final uri = Uri.tryParse(kPurchasePageUrl);
    if (uri == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) {
        return;
      }
    } catch (_) {
      // 打不开外部浏览器时退化为复制链接。
    }
    await Clipboard.setData(const ClipboardData(text: kPurchasePageUrl));
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(context.t(LocaleKeys.settingsLicenseCopyLinkDone))),
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

    final cards = <Widget>[
      _PlanCard(
        title: context.t(LocaleKeys.settingsLicenseTierFree),
        tagline: context.t(LocaleKeys.settingsLicenseFreeTagline),
        price: context.t(LocaleKeys.settingsLicenseFreePrice),
        features: context.t(LocaleKeys.settingsLicenseFreeFeatures),
        isCurrent: _state.tier == LicenseTier.free,
        actionLabel: context.t(LocaleKeys.settingsLicenseFreeCta),
        onAction: null,
      ),
      _PlanCard(
        title: context.t(LocaleKeys.settingsLicenseTierStandard),
        tagline: context.t(LocaleKeys.settingsLicenseStandardTagline),
        price: context.t(LocaleKeys.settingsLicenseStandardPrice),
        features: context.t(LocaleKeys.settingsLicenseStandardFeatures),
        isCurrent: _state.tier == LicenseTier.standard,
        actionLabel: context.t(LocaleKeys.settingsLicenseBuyStandard),
        onAction: _openPurchase,
        highlighted: true,
      ),
      _PlanCard(
        title: context.t(LocaleKeys.settingsLicenseTierPro),
        tagline: context.t(LocaleKeys.settingsLicenseProTagline),
        price: context.t(LocaleKeys.settingsLicenseProPrice),
        features: context.t(LocaleKeys.settingsLicenseProFeatures),
        isCurrent: _state.tier == LicenseTier.pro,
        actionLabel: context.t(LocaleKeys.settingsLicenseBuyPro),
        onAction: _openPurchase,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(RevericSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(LocaleKeys.settingsLicensePricingTitle),
            style: typo.heading2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            context.t(LocaleKeys.settingsLicensePricingSubtitle),
            style: typo.ui.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: RevericSpacing.lg),
          // 当前状态条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(RevericSpacing.md),
            decoration: BoxDecoration(
              color: colors.surfaceDim,
              borderRadius: BorderRadius.circular(RevericRadius.medium),
            ),
            child: _loading
                ? Text(
                    context.t(LocaleKeys.settingsLicenseLoading),
                    style: typo.ui.copyWith(color: colors.textSecondary),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.t(
                                LocaleKeys.settingsLicenseCurrentTier,
                                namedArgs: <String, String>{
                                  'tier': _tierLabel(context),
                                },
                              ),
                              style: typo.uiSemibold.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          if (_expiryText(context) != null)
                            Text(
                              _expiryText(context)!,
                              style: typo.ui.copyWith(color: colors.textSecondary),
                            ),
                        ],
                      ),
                      if (_state.isActivated) ...[
                        const SizedBox(height: RevericSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.t(
                                  LocaleKeys.settingsLicenseDeviceBound,
                                  namedArgs: <String, String>{
                                    'device': _deviceLabel(),
                                  },
                                ),
                                style: typo.ui.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _activating ? null : _deactivate,
                              child: Text(
                                context.t(LocaleKeys.settingsLicenseDeactivate),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: RevericSpacing.x2l),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 880;
              if (isWide) {
                return IntrinsicHeight(
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
          const SizedBox(height: RevericSpacing.x4l),
          Text(
            context.t(LocaleKeys.settingsLicenseCodeLabel),
            style: typo.uiSemibold.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  decoration: InputDecoration(
                    hintText: context.t(LocaleKeys.settingsLicenseCodeHint),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: RevericSpacing.md),
              ElevatedButton(
                onPressed: _activating ? null : _activate,
                child: Text(context.t(LocaleKeys.settingsLicenseActivate)),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            context.t(LocaleKeys.settingsLicenseDescription),
            style: typo.ui.copyWith(color: colors.textMuted),
          ),
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
    this.onAction,
    this.highlighted = false,
  });

  final String title;
  final String tagline;
  final String price;
  final String features;
  final String actionLabel;
  final bool isCurrent;
  final VoidCallback? onAction;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final borderColor = isCurrent || highlighted ? colors.accent : colors.border;
    final featureLines = features
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        border: Border.all(
          color: borderColor,
          width: isCurrent || highlighted ? 1.5 : 1,
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
                Container(
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
                    style: typo.uiSmall.copyWith(color: colors.onAccent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            price,
            style: typo.heading2.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 26,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            tagline,
            style: typo.uiSmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: RevericSpacing.md),
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
          const SizedBox(height: RevericSpacing.md),
          SizedBox(
            width: double.infinity,
            child: onAction == null
                ? OutlinedButton(
                    onPressed: null,
                    child: Text(actionLabel),
                  )
                : ElevatedButton(
                    onPressed: onAction,
                    child: Text(actionLabel),
                  ),
          ),
        ],
      ),
    );
  }
}
