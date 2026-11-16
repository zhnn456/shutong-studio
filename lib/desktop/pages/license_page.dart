// 职责: 授权与商业版本整页入口 — 首页左侧栏「授权」点击后进入，
//   以独立页面而非弹窗呈现，避免打断创作流程。
// 关联文件:
//   lib/desktop/widgets/license/license_pricing_view.dart
//   lib/desktop/pages/home.dart
//   lib/shared/theme/reveric_icons.dart
import 'package:flutter/material.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/theme/theme.dart';
import '../widgets/license/license_pricing_view.dart';

/// 授权与商业方案页。
class LicensePage extends StatelessWidget {
  const LicensePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: RevericSizes.iconButtonSize + RevericSpacing.x2l,
        leading: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: RevericSpacing.sm),
            child: IconButton(
              tooltip: context.t(LocaleKeys.settingsLicenseBack),
              icon: RevericIcon(
                RevericIcons.arrow_back,
                size: RevericSizes.buttonIconSize,
                color: colors.textPrimary,
              ),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        titleSpacing: 0,
        title: Text(
          context.t(LocaleKeys.settingsLicense),
          style: typo.uiSemibold.copyWith(color: colors.textPrimary),
        ),
      ),
      body: const LicensePricingView(),
    );
  }
}
