// 职责: 本地授权状态的读写与授权码校验（MVP 骨架）。
//   - 状态用 SharedPreferences 持久化，并附带 HMAC-SHA256 签名，防止用户手改 JSON 解锁。
//   - 授权码使用内置对称密钥做 HMAC 校验，可离线激活。
// 关联文件:
//   lib/shared/models/license.dart
//   lib/shared/services/device_id_service.dart
//   lib/shared/services/novel_actions.dart
//   lib/desktop/widgets/settings/settings_license_section.dart
//
// 【重要 · MVP 边界】
//   当前为可跑通的最小骨架：授权码用内置对称密钥 HMAC 校验，密钥随客户端分发，理论上可被逆向伪造。
//   正式对外发码之前，必须：
//     1. 改为服务端 Ed25519 私钥签名、客户端只持公钥验签（crypto 包不含 Ed25519，需引入 pointycastle）；
//     2. 把 kEnforceDeviceBinding 置为 true，启用一码一机校验；
//     3. 授权码 issuance 由 Keygate 自托管许可服务在支付回调后自动签发。
//
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_id_service.dart';
import '../models/license.dart';

/// 是否强制一码一机绑定（换机即失效）。MVP 先关闭，正式发码前开启。
const bool kEnforceDeviceBinding = false;

/// 授权激活结果。
class LicenseActivationResult {
  const LicenseActivationResult.success(this.state) : message = null;

  const LicenseActivationResult.failure(this.message) : state = null;

  final LicenseState? state;
  final String? message;

  bool get isSuccess => state != null;
}

/// 授权状态读写与授权码校验。
class LicenseService {
  static const _stateKey = 'license_state_v1';

  // ---------------- 读取 / 保存 ----------------

  /// 读取当前授权状态；未激活、签名损坏或指纹不匹配时一律回退为免费版。
  static Future<LicenseState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stateKey);
    if (raw == null || raw.isEmpty) {
      return const LicenseState.free();
    }
    final parsed = _decodeSigned(raw);
    if (parsed == null) {
      return const LicenseState.free();
    }
    final state = LicenseState.fromJson(parsed);
    if (kEnforceDeviceBinding && state.isActivated) {
      final deviceId = await DeviceIdService().getOrCreate();
      if (state.boundDeviceId != null && state.boundDeviceId != deviceId) {
        return const LicenseState.free();
      }
    }
    return state;
  }

  /// 清空本地授权（调试/退订用）。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_stateKey);
  }

  static Future<void> _save(LicenseState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, _encodeSigned(state.toJson()));
  }

  // ---------------- 授权码激活 ----------------

  /// 授权码格式：`SHT.<base64url(payloadJson)>.<base64url(hmacSha256)>`。
  /// payloadJson: {"t":"standard|pro","e":"2027-01-01T00:00:00Z|null","id":"lic_xxx"}。
  static Future<LicenseActivationResult> activate(String code) async {
    final trimmed = code.trim();
    final parts = trimmed.split('.');
    if (parts.length != 3 || parts[0] != 'SHT') {
      return const LicenseActivationResult.failure('invalid_format');
    }
    final payloadBytes = _tryBase64UrlDecode(parts[1]);
    final sigBytes = _tryBase64UrlDecode(parts[2]);
    if (payloadBytes == null || sigBytes == null) {
      return const LicenseActivationResult.failure('invalid_format');
    }
    if (!_constantTimeEquals(_hmac(payloadBytes), sigBytes)) {
      return const LicenseActivationResult.failure('invalid_signature');
    }

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(utf8.decode(payloadBytes));
      payload = decoded as Map<String, dynamic>;
    } catch (_) {
      return const LicenseActivationResult.failure('invalid_payload');
    }

    final tier = LicenseTier.values.firstWhere(
      (value) => value.name == (payload['t'] as String?),
      orElse: () => LicenseTier.free,
    );
    if (tier == LicenseTier.free) {
      return const LicenseActivationResult.failure('invalid_tier');
    }
    final expiresRaw = payload['e'] as String?;
    final expiresAt = expiresRaw == null ? null : DateTime.tryParse(expiresRaw);
    if (expiresRaw != null && expiresAt == null) {
      return const LicenseActivationResult.failure('invalid_payload');
    }
    final licenseId = payload['id'] as String?;
    final deviceId = await DeviceIdService().getOrCreate();

    final state = LicenseState(
      tier: tier,
      expiresAt: expiresAt,
      activationCode: trimmed,
      boundDeviceId: deviceId,
      licenseId: licenseId,
    );
    await _save(state);
    return LicenseActivationResult.success(state);
  }

  // ---------------- 内部：签名缓存 ----------------

  static String _encodeSigned(Map<String, dynamic> json) {
    final payload = jsonEncode(json);
    final payloadB64 = base64Url.encode(utf8.encode(payload));
    final sigB64 = base64Url.encode(_hmac(utf8.encode(payload)));
    return '$payloadB64.$sigB64';
  }

  static Map<String, dynamic>? _decodeSigned(String raw) {
    final parts = raw.split('.');
    if (parts.length != 2) {
      return null;
    }
    final payloadBytes = _tryBase64UrlDecode(parts[0]);
    final sigBytes = _tryBase64UrlDecode(parts[1]);
    if (payloadBytes == null || sigBytes == null) {
      return null;
    }
    if (!_constantTimeEquals(_hmac(payloadBytes), sigBytes)) {
      return null;
    }
    try {
      final decoded = jsonDecode(utf8.decode(payloadBytes));
      return decoded as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static List<int> _hmac(List<int> bytes) {
    return Hmac(sha256, utf8.encode(kLicenseHmacSecret)).convert(bytes).bytes;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static List<int>? _tryBase64UrlDecode(String value) {
    try {
      return base64Url.decode(base64Url.normalize(value));
    } catch (_) {
      return null;
    }
  }
}
