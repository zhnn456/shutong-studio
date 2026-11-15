part of 'settings_dialog.dart';

/// 「授权」设置分区：展示授权等级与到期、提供授权码激活与购买入口。
/// 依赖父 library（settings_dialog.dart）已引入的 material / theme / localization，
///
/// 以及 license 模型与服务。
class _LicenseSettingsSection extends StatefulWidget {
  const _LicenseSettingsSection();

  @override
  State<_LicenseSettingsSection> createState() =>
      _LicenseSettingsSectionState();
}

class _LicenseSettingsSectionState extends State<_LicenseSettingsSection> {
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
    final state = await LicenseService.load();
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.t(LocaleKeys.settingsLicenseActivateFailed)),
        ),
      );
    }
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

  String _expiryLabel(BuildContext context) {
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

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(RevericSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(LocaleKeys.settingsLicense),
            style: typo.heading2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            context.t(LocaleKeys.settingsLicenseDescription),
            style: typo.ui.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: RevericSpacing.x2l),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(RevericSpacing.lg),
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
                      Text(
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
                      if (_state.isActivated) ...[
                        const SizedBox(height: 4),
                        Text(
                          _expiryLabel(context),
                          style: typo.ui.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: RevericSpacing.x2l),
          Text(
            context.t(LocaleKeys.settingsLicenseCodeLabel),
            style: typo.uiSemibold.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.sm),
          TextField(
            controller: _codeController,
            decoration: InputDecoration(
              hintText: context.t(LocaleKeys.settingsLicenseCodeHint),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: RevericSpacing.lg),
          Row(
            children: [
              ElevatedButton(
                onPressed: _activating ? null : _activate,
                child: Text(context.t(LocaleKeys.settingsLicenseActivate)),
              ),
              const SizedBox(width: RevericSpacing.md),
              OutlinedButton(
                onPressed: _openPurchase,
                child: Text(context.t(LocaleKeys.settingsLicenseBuy)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
