// 职责: 授权（License）领域模型与常量 — 授权等级、授权状态、免费版限额、超限异常、购买落点。
//   - 授权数据来自 Keygate 自托管许可服务签发的 Ed25519 token，客户端只持公钥验签。
//   - 客户端不再持有任何对称密钥，本地无法伪造授权。
// 关联文件:
//   lib/shared/services/license_service.dart
//   lib/shared/services/keygate/keygate_client.dart
//   lib/shared/services/keygate/keygate_token.dart
//   lib/desktop/widgets/license/license_pricing_view.dart
//   lib/shared/services/novel_actions.dart
//

/// 授权等级。
enum LicenseTier { free, standard, pro }

/// 免费版本地作品数量上限（只统计正式作品，不含快速开书占位草稿）。
const int kFreeTierNovelLimit = 1;

/// Keygate 许可服务地址（自托管）。
/// 服务器上线后改用 `--dart-define=KEYGATE_BASE_URL=https://your-domain` 覆盖，
/// 或直接改这里默认值。
const String kKeygateBaseUrl = String.fromEnvironment(
  'KEYGATE_BASE_URL',
  defaultValue: 'https://keygate.de5.net',
);

/// Keygate 授权 token 验签公钥（Ed25519，hex 编码）。
/// 取自 `GET {base}/api/v1/license/pubkey`，一次性内置进客户端。
/// 为空时无法验签，视为未激活（服务器上线前保持为空是预期行为）。
const String kKeygatePublicKeyHex = String.fromEnvironment(
  'KEYGATE_PUBKEY',
  defaultValue:
      '5c345f515036ee78a1e4efe749edee4705a277acafe5e488c48bf042954e787b',
);

/// 离线宽限：token 的 check-in 时间过期后，仍允许离线使用的天数。
/// 超过宽限且无法联网刷新时判定为未授权。
const int kKeygateOfflineGraceDays = 3;

/// 购买/升级落地入口。当前没有独立商城，走邮件下单：
/// 客户发邮件说明要买的套餐 → 回授权码。有商城页后只需替换这一行的 URL。
const String kPurchasePageUrl = 'mailto:282063152@qq.com';

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
    this.licenseKey,
    this.token,
    this.checkInAt,
    this.planName,
    this.deviceId,
    this.licenseId,
    this.features = const <String, dynamic>{},
  });

  const LicenseState.free()
    : tier = LicenseTier.free,
      expiresAt = null,
      licenseKey = null,
      token = null,
      checkInAt = null,
      planName = null,
      deviceId = null,
      licenseId = null,
      features = const <String, dynamic>{};

  final LicenseTier tier;

  /// 授权本身到期时间（token 的 `vun`）；为空表示永久授权。
  final DateTime? expiresAt;

  /// 用户输入的授权码（Keygate 的 `KG-...`）。
  final String? licenseKey;

  /// Keygate 签发的 Ed25519 token，启动时本地验签。
  final String? token;

  /// token 的 `exp`：到这个时间需要联网 verify 刷新。
  final DateTime? checkInAt;

  /// 服务端套餐名（如 Standard / 专业版），用于展示。
  final String? planName;

  /// 激活绑定的设备指纹（Keygate `identifier`）。
  final String? deviceId;

  final String? licenseId;

  /// 服务端下发的功能清单（token 的 `ftr`），可包含 tier、max_novels 等。
  final Map<String, dynamic> features;

  bool get isFree => tier == LicenseTier.free;

  bool get isActivated => tier != LicenseTier.free;

  bool get isPermanent => expiresAt == null;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// 是否需要在下次启动时联网刷新 token（过期超过宽限才算问题）。
  bool get needsCheckIn {
    final at = checkInAt;
    if (at == null) {
      return true;
    }
    return DateTime.now().isAfter(at);
  }

  /// 离线宽限是否已用尽（过期超过 kKeygateOfflineGraceDays 天）。
  bool get isCheckInGraceOver {
    final at = checkInAt;
    if (at == null) {
      return true;
    }
    return DateTime.now().isAfter(
      at.add(const Duration(days: kKeygateOfflineGraceDays)),
    );
  }

  /// 作品数量上限；null 表示不限。
  int? get novelLimit {
    final raw = features['max_novels'];
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return isActivated ? null : kFreeTierNovelLimit;
  }

  /// 可用 = 已激活、未过期，且离线宽限未用尽。
  bool get isUsable => isActivated && !isExpired && !isCheckInGraceOver;

  LicenseState copyWith({
    LicenseTier? tier,
    DateTime? expiresAt,
    String? licenseKey,
    String? token,
    DateTime? checkInAt,
    String? planName,
    String? deviceId,
    String? licenseId,
    Map<String, dynamic>? features,
  }) {
    return LicenseState(
      tier: tier ?? this.tier,
      expiresAt: expiresAt ?? this.expiresAt,
      licenseKey: licenseKey ?? this.licenseKey,
      token: token ?? this.token,
      checkInAt: checkInAt ?? this.checkInAt,
      planName: planName ?? this.planName,
      deviceId: deviceId ?? this.deviceId,
      licenseId: licenseId ?? this.licenseId,
      features: features ?? this.features,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'tier': tier.name,
    'expiresAt': expiresAt?.toIso8601String(),
    'licenseKey': licenseKey,
    'token': token,
    'checkInAt': checkInAt?.toIso8601String(),
    'planName': planName,
    'deviceId': deviceId,
    'licenseId': licenseId,
    'features': features,
  };

  static LicenseState fromJson(Map<String, dynamic> json) {
    final tierName = json['tier'] as String? ?? 'free';
    final tier = LicenseTier.values.firstWhere(
      (value) => value.name == tierName,
      orElse: () => LicenseTier.free,
    );
    final expiresRaw = json['expiresAt'] as String?;
    final checkInRaw = json['checkInAt'] as String?;
    final featuresRaw = json['features'];
    return LicenseState(
      tier: tier,
      expiresAt: expiresRaw == null ? null : DateTime.tryParse(expiresRaw),
      licenseKey: json['licenseKey'] as String?,
      token: json['token'] as String?,
      checkInAt: checkInRaw == null ? null : DateTime.tryParse(checkInRaw),
      planName: json['planName'] as String?,
      deviceId: json['deviceId'] as String?,
      licenseId: json['licenseId'] as String?,
      features: featuresRaw is Map
          ? featuresRaw.map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : const <String, dynamic>{},
    );
  }
}
