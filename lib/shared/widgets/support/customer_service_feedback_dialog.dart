// 职责: 客服反馈弹窗 — 首页之外的入口（关于菜单、授权页等）以弹窗展示客服反馈内容。
//   内容本体在 CustomerServiceFeedbackView，与首页侧栏「客服反馈」内嵌页共用。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/widgets/support/customer_service_feedback_view.dart
//   lib/desktop/pages/customer_service_page.dart
//   assets/translations/zh-CN/support.json
//   assets/translations/en/support.json
import 'package:flutter/material.dart';

import 'package:reveric/shared/localization/app_localization.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/theme/theme.dart';
import '../../components/reveric_button.dart';
import '../../components/reveric_dialog.dart';
import 'customer_service_feedback_view.dart';

/// 展示客服反馈的入口弹窗：官方客服二维码、写留言表单、本机留言记录与联系邮箱。
Future<void> showCustomerServiceFeedbackDialog({
  required BuildContext context,
}) async {
  final dialogWidth = MediaQuery.sizeOf(context).width.clamp(320.0, 440.0) - 48;

  await showRevericDialog<void>(
    context: context,
    builder: (dialogContext) {
      return RevericDialog.panel(
        title: Text(dialogContext.t(LocaleKeys.supportTitle)),
        content: SizedBox(
          width: dialogWidth,
          child: const SingleChildScrollView(
            child: CustomerServiceFeedbackView(),
          ),
        ),
        width: dialogWidth + RevericSpacing.x4l * 2,
        actions: [
          RevericButton.secondary(
            label: dialogContext.t(LocaleKeys.commonClose),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      );
    },
  );
}
