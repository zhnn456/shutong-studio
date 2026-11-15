// 职责: 授权与商业版本整页入口 — 左侧栏「升级授权」点击后进入，
//   以独立页面而非弹窗呈现，避免打断创作流程。
// 关联文件:
//   lib/desktop/widgets/license/license_pricing_view.dart
//   lib/desktop/widgets/sidebar/rail.dart
//   lib/shared/localization/locale_keys.dart
import 'package:flutter/material.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../widgets/license/license_pricing_view.dart';

/// 授权与商业方案页。
class LicensePage extends StatelessWidget {
  const LicensePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t(LocaleKeys.settingsLicense)),
        elevation: 0,
      ),
      body: const LicensePricingView(),
    );
  }
}
