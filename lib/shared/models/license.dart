// 职责: 授权（License）领域模型与常量 — 授权等级、授权状态、免费版限额、超限异常、购买落点。
// 关联文件:
//   lib/shared/services/license_service.dart
//   lib/desktop/widgets/settings/settings_license_section.dart
//   lib/shared/services/novel_actions.dart
//

/// 授权等级。
enum LicenseTier { free, standard, pro }

/// 免费版本地作品数量上限（只统计正式作品，不含快速开书占位草稿）。
const int kFreeTierNovelLimit = 1;

/// 客户端授权码验签密钥（MVP 骨架用对称 HMAC）。
/// 正式对外发码前必须改为服务端 Ed25519 私钥签名 + 客户端公钥验签，
/// 详见 license_service.dart 文件头说明。
const String kLicenseHmacSecret = 'shutong-license-v1-2026';

/// 购买/升级页面地址。占位值，上线前替换为真实落地页（含支付入口与源码获取入口）。
const String kPurchasePageUrl = 'https://github.com/zhnn456/shutong-studio';

/// 免费版超出作品上限时抛出，UI 层据此引导升级，而不是显示通用失败。
class NovelFreeLimitException implements Exception {
  const NovelFreeLimitException(this.limit);

  /// 触发时的免费额度。
  final int limit;

  @override
  String toString() => 'NovelFreeLimitException(limit: $limit)';
}

/// 当前授权状态。只承载数据，校验与持久化在 LicenseService。
class LicenseState {
  const LicenseState({
    required this.tier,
    this.expiresAt,
    this.activationCode,
    this.boundDeviceId,
    this.licenseId,
  });

  const LicenseState.free()
    : tier = LicenseTier.free,
      expiresAt = null,
      activationCode = null,
      boundDeviceId = null,
      licenseId = null;

  final LicenseTier tier;

  /// 到期时间；为空表示永久授权。
  final DateTime? expiresAt;
  final String? activationCode;

  /// 激活时绑定的机器指纹；换机校验用。
  final String? boundDeviceId;
  final String? licenseId;

  bool get isFree => tier == LicenseTier.free;

  bool get isActivated => tier != LicenseTier.free;

  bool get isPermanent => expiresAt == null;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// 可用 = 已激活且未过期。
  bool get isUsable => isActivated && !isExpired;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'tier': tier.name,
    'expiresAt': expiresAt?.toIso8601String(),
    'activationCode': activationCode,
    'boundDeviceId': boundDeviceId,
    'licenseId': licenseId,
  };

  static LicenseState fromJson(Map<String, dynamic> json) {
    final tierName = json['tier'] as String? ?? 'free';
    final tier = LicenseTier.values.firstWhere(
      (value) => value.name == tierName,
      orElse: () => LicenseTier.free,
    );
    final expiresRaw = json['expiresAt'] as String?;
    return LicenseState(
      tier: tier,
      expiresAt: expiresRaw == null ? null : DateTime.tryParse(expiresRaw),
      activationCode: json['activationCode'] as String?,
      boundDeviceId: json['boundDeviceId'] as String?,
      licenseId: json['licenseId'] as String?,
    );
  }
}
