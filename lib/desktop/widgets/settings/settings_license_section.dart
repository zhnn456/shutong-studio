part of 'settings_dialog.dart';

/// 设置页「授权」分区 — 与左侧栏「升级授权」一级入口共用同一套内容，
/// 避免两套定价信息不一致。
class _LicenseSettingsSection extends StatelessWidget {
  const _LicenseSettingsSection();

  @override
  Widget build(BuildContext context) => const LicensePricingView();
}
