// 职责: 校验 Keygate 签发的授权 token（Ed25519），解析其中的 claims。
//   - token 形如 `<base64url(payload)>.<base64url(signature)>`，签名覆盖 payload 段原文。
//   - 客户端只持公钥，无需联网即可判断本地授权是否仍然有效。
// 关联文件:
//   lib/shared/models/license.dart        （公钥常量、离线宽限常量）
//   lib/shared/services/license_service.dart
//   lib/shared/services/keygate/keygate_client.dart
//
// Keygate token claims（时间均为 Unix 秒）:
//   lid 授权 ID / pid 产品 / pln 套餐名 / sts 状态 / did 绑定的设备标识
//   ftr 功能清单 / iat 签发时间 / exp 下次校验时间
//   vun 授权结束时间（缺省=永久）/ grc 宽限天数 / upd 可安装更新截止时间
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// 验签后的 token 内容。
class KeygateClaims {
  const KeygateClaims({
    required this.licenseId,
    required this.productId,
    required this.planName,
    required this.status,
    required this.deviceId,
    required this.features,
    required this.issuedAt,
    required this.checkInAt,
    required this.licenseEnd,
    required this.graceDays,
    required this.updatesUntil,
    required this.raw,
  });

  final String licenseId;
  final String productId;
  final String planName;
  final String status;
  final String deviceId;
  final Map<String, dynamic> features;
  final DateTime issuedAt;
  final DateTime checkInAt;
  final DateTime? licenseEnd;
  final int graceDays;
  final DateTime? updatesUntil;
  final Map<String, dynamic> raw;
}

/// token 验签与解析。
class KeygateToken {
  const KeygateToken._();

  /// token 可能带 DER/SPKI 前缀，统一剥掉只留 32 字节原文。
  static const String _ed25519DerPrefix = '302a300506032b6570032100';

  /// 验签并解析 token。签名错误、payload 损坏、或签发对象不是本机时返回 null。
  static Future<KeygateClaims?> verify({
    required String token,
    required String publicKeyHex,
    required String identifier,
  }) async {
    if (token.isEmpty || publicKeyHex.isEmpty || identifier.isEmpty) {
      return null;
    }
    final parts = token.split('.');
    if (parts.length != 2) {
      return null;
    }
    final payloadSegment = parts[0];
    final signatureBytes = _tryBase64UrlDecode(parts[1]);
    if (signatureBytes == null) {
      return null;
    }

    final publicKeyBytes = _tryHexDecode(_stripDerPrefix(publicKeyHex));
    if (publicKeyBytes == null || publicKeyBytes.length != 32) {
      return null;
    }

    bool valid;
    try {
      final algorithm = Ed25519();
      valid = await algorithm.verify(
        utf8.encode(payloadSegment),
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(
            publicKeyBytes,
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } catch (_) {
      return null;
    }
    if (!valid) {
      return null;
    }

    final payloadBytes = _tryBase64UrlDecode(payloadSegment);
    if (payloadBytes == null) {
      return null;
    }
    Map<String, dynamic> claims;
    try {
      final decoded = jsonDecode(utf8.decode(payloadBytes));
      claims = (decoded as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }

    final did = claims['did'] as String? ?? '';
    if (did.isEmpty || did != identifier) {
      // token 是签发给另一台机器的。
      return null;
    }

    final ftrRaw = claims['ftr'];
    final features = ftrRaw is Map
        ? ftrRaw.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};

    return KeygateClaims(
      licenseId: claims['lid'] as String? ?? '',
      productId: claims['pid'] as String? ?? '',
      planName: claims['pln'] as String? ?? '',
      status: claims['sts'] as String? ?? '',
      deviceId: did,
      features: features,
      issuedAt: _unix(claims['iat']) ?? DateTime.now(),
      checkInAt: _unix(claims['exp']) ?? DateTime.now(),
      licenseEnd: _unix(claims['vun']),
      graceDays: _int(claims['grc']) ?? 0,
      updatesUntil: _unix(claims['upd']),
      raw: claims,
    );
  }

  static String _stripDerPrefix(String hex) {
    final lower = hex.toLowerCase().trim();
    if (lower.length == 64 + _ed25519DerPrefix.length &&
        lower.startsWith(_ed25519DerPrefix)) {
      return lower.substring(_ed25519DerPrefix.length);
    }
    return lower;
  }

  static DateTime? _unix(Object? value) {
    final seconds = _int(value);
    if (seconds == null || seconds <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).toLocal();
  }

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static List<int>? _tryHexDecode(String hex) {
    if (hex.length.isOdd) {
      return null;
    }
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte == null) {
        return null;
      }
      bytes.add(byte);
    }
    return bytes;
  }

  static List<int>? _tryBase64UrlDecode(String value) {
    try {
      return base64Url.decode(base64Url.normalize(value));
    } catch (_) {
      return null;
    }
  }
}

/// 套餐 → 授权等级。服务端在 features 里下发 `tier` 时以它为准，
/// 否则按套餐名做关键词匹配，兜底为标准版。
LicenseTierGuess guessTier({
  required String planName,
  required Map<String, dynamic> features,
}) {
  final explicit = features['tier']?.toString().toLowerCase();
  if (explicit != null) {
    if (explicit == 'pro') {
      return LicenseTierGuess.pro;
    }
    if (explicit == 'standard') {
      return LicenseTierGuess.standard;
    }
    if (explicit == 'free') {
      return LicenseTierGuess.free;
    }
  }
  final name = planName.toLowerCase();
  if (name.contains('pro') || name.contains('专业') || name.contains('旗舰')) {
    return LicenseTierGuess.pro;
  }
  if (name.contains('free') || name.contains('免费')) {
    return LicenseTierGuess.free;
  }
  return LicenseTierGuess.standard;
}

/// 套餐猜测结果，避免与 models 层枚举耦合过度。
enum LicenseTierGuess { free, standard, pro }
