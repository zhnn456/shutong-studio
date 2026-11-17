// 职责: 授权与商业版本页入口 — 首页侧栏「授权」选中后在主区域内嵌渲染（保留侧栏），
//   不再以独立整页 + 返回箭头的形式打开。
// 关联文件:
//   lib/desktop/widgets/license/license_pricing_view.dart
//   lib/desktop/pages/home.dart
//   lib/desktop/widgets/agent_management/home_management_cards.dart
//   lib/shared/theme/reveric_icons.dart
import 'package:flutter/material.dart';

import '../../shared/localization/locale_keys.dart';
import '../../shared/theme/theme.dart';
import '../widgets/agent_management/home_management_cards.dart';
import '../widgets/license/license_pricing_view.dart';

/// 首页内嵌形态的授权页：与设置页共用同一页头容器，切换时左侧侧栏保持可见。
class DesktopLicensePage extends StatelessWidget {
  const DesktopLicensePage({
    super.key,
    required this.headerGestureExclusionKey,
    this.headerTrailingInset = 0,
    this.headerAction,
  });

  final GlobalKey headerGestureExclusionKey;
  final double headerTrailingInset;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    return HomeManagementScaffold(
      headerGestureExclusionKey: headerGestureExclusionKey,
      headerTrailingInset: headerTrailingInset,
      secondaryAction: headerAction,
      icon: RevericIcons.crown,
      titleKey: LocaleKeys.settingsLicense,
      child: const LicensePricingView(),
    );
  }
}
