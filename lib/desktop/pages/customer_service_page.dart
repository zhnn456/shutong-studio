// 职责: 首页内嵌客服反馈页 — 侧栏「客服反馈」选中后主区域渲染，左侧侧栏保持可见。
// 关联文件:
//   lib/shared/widgets/support/customer_service_feedback_view.dart
//   lib/desktop/pages/home.dart
//   lib/desktop/widgets/agent_management/home_management_cards.dart
//   lib/shared/theme/reveric_icons.dart
import 'package:flutter/material.dart';

import '../../shared/localization/locale_keys.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/support/customer_service_feedback_view.dart';
import '../widgets/agent_management/home_management_cards.dart';

/// 客服反馈页（首页内嵌形态）：与设置、授权共用同一页头容器。
class DesktopCustomerServicePage extends StatelessWidget {
  const DesktopCustomerServicePage({
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
      icon: RevericIcons.chat_rounded,
      titleKey: LocaleKeys.homeNavCustomerService,
      child: const SingleChildScrollView(
        padding: EdgeInsets.all(RevericSpacing.x4l),
        child: CustomerServiceFeedbackView(),
      ),
    );
  }
}
