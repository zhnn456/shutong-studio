// 职责: 本地授权状态的读写与 Keygate 授权码激活/刷新/解绑。
//   - 授权来源: 自托管 Keygate 许可服务签发的 Ed25519 token（见 keygate/）。
//   - 本地只存 {授权码, 设备指纹, token}，启动时用内置公钥验签，不联网也能判断授权。
//   - 客户端不持有任何对称密钥，改本地数据会直接导致验签失败。
// 关联文件:
//   lib/shared/models/license.dart
//   lib/shared/services/device_id_service.dart
//   lib/shared/services/keygate/keygate_client.dart
//   lib/shared/services/keygate/keygate_token.dart
//   lib/shared/services/novel_actions.dart
//   lib/desktop/widgets/license/license_pricing_view.dart
//
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'device_id_service.dart';
import 'keygate/keygate_client.dart';
import 'keygate/keygate_token.dart';
import '../models/license.dart';

/// 授权操作结果。message 为本地化 key，由 UI 侧翻译。
class LicenseActivationResult {
  const LicenseActivationResult.success(this.state)
    : message = null,
      errorCode = null;

  const LicenseActivationResult.failure(this.message, {this.errorCode})
    : state = null;

  final LicenseState? state;
  final String? message;
  final String? errorCode;

  bool get isSuccess => state != null;
}

/// 授权状态读写与 Keygate 交互。
class LicenseService {
  static const _stateKey = 'license_state_v2';

  // ---------------- 读取 / 保存 ----------------

  /// 读取当前授权状态：本地验签 token，签名无效或设备不匹配一律回退免费版。
  static Future<LicenseState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stateKey);
    if (raw == null || raw.isEmpty) {
      return const LicenseState.free();
    }
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const LicenseState.free();
      }
      json = decoded.cast<String, dynamic>();
    } catch (_) {
      return const LicenseState.free();
    }

    final state = LicenseState.fromJson(json);
    if (!state.isActivated) {
      return state;
    }
    final token = state.token;
    final licenseKey = state.licenseKey;
    if (token == null || licenseKey == null) {
      return const LicenseState.free();
    }
    final deviceId = state.deviceId ?? await DeviceIdService().getOrCreate();
    final claims = await KeygateToken.verify(
      token: token,
      publicKeyHex: kKeygatePublicKeyHex,
      identifier: deviceId,
    );
    if (claims == null) {
      // 公钥未配置、token 被篡改、或 token 属于另一台设备。
      return const LicenseState.free();
    }
    return _stateFromClaims(state, claims);
  }

  /// 清空本地授权。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_stateKey);
  }

  // ---------------- 激活 / 刷新 / 解绑 --------------

  /// 用 Keygate 授权码激活当前设备。
  /// 流程: activate → 拿到签名 token → 本地验签 → 落盘。
  static Future<LicenseActivationResult> activate(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return const LicenseActivationResult.failure(
        'settingsLicenseActivateFailed',
      );
    }
    if (kKeygatePublicKeyHex.isEmpty) {
      return const LicenseActivationResult.failure(
        'settingsLicenseServiceNotConfigured',
      );
    }

    final deviceId = await DeviceIdService().getOrCreate();
    final client = KeygateClient(baseUrl: kKeygateBaseUrl);
    KeygateResult result;
    try {
      result = await client.activate(
        licenseKey: trimmed,
        identifier: deviceId,
        label: _deviceLabel(),
      );
    } finally {
      client.dispose();
    }
    if (!result.success) {
      return LicenseActivationResult.failure(
        _messageKeyOf(result),
        errorCode: result.errorCode?.name,
      );
    }
    final token = result.token;
    if (token == null) {
      return const LicenseActivationResult.failure(
        'settingsLicenseActivateFailed',
      );
    }
    final claims = await KeygateToken.verify(
      token: token,
      publicKeyHex: kKeygatePublicKeyHex,
      identifier: deviceId,
    );
    if (claims == null) {
      return const LicenseActivationResult.failure(
        'settingsLicenseSignatureInvalid',
      );
    }

    final state = LicenseState(
      tier: _tierOf(claims, result.data),
      expiresAt: claims.licenseEnd,
      licenseKey: trimmed,
      token: token,
      checkInAt: claims.checkInAt,
      planName: _planNameOf(result.data, claims),
      deviceId: deviceId,
      licenseId: claims.licenseId,
      features: _featuresOf(result.data, claims),
    );
    await _save(state);
    return LicenseActivationResult.success(state);
  }

  /// 需要时联网刷新 token（token 过期、或首次安装后启动）。
  /// 网络不可达时保留本地授权，交给离线宽限处理。
  static Future<LicenseState> refreshIfNeeded() async {
    final current = await load();
    if (!current.isActivated || !current.needsCheckIn) {
      return current;
    }
    return _refreshWithKey(current);
  }

  static Future<LicenseState> _refreshWithKey(LicenseState current) async {
    final licenseKey = current.licenseKey;
    final deviceId = current.deviceId;
    if (licenseKey == null || deviceId == null) {
      return current;
    }
    final client = KeygateClient(baseUrl: kKeygateBaseUrl);
    KeygateResult result;
    try {
      result = await client.verify(
        licenseKey: licenseKey,
        identifier: deviceId,
      );
    } finally {
      client.dispose();
    }

    if (!result.success) {
      // 404 = 授权已失效（吊销/过期/换机）；网络与服务端错误保留本地状态走宽限。
      if (result.errorCode == KeygateErrorCode.notFound) {
        await clear();
        return const LicenseState.free();
      }
      return current;
    }

    final token = result.token;
    if (token == null) {
      return current;
    }
    final claims = await KeygateToken.verify(
      token: token,
      publicKeyHex: kKeygatePublicKeyHex,
      identifier: deviceId,
    );
    if (claims == null) {
      return current;
    }
    final state = _stateFromClaims(current, claims, serverData: result.data);
    await _save(state);
    return state;
  }

  /// 解绑当前设备（换机用）：服务端释放名额，本地清空授权。
  static Future<bool> deactivateCurrentDevice() async {
    final current = await load();
    final licenseKey = current.licenseKey;
    final deviceId = current.deviceId;
    if (licenseKey != null && deviceId != null && kKeygateBaseUrl.isNotEmpty) {
      final client = KeygateClient(baseUrl: kKeygateBaseUrl);
      try {
        await client.deactivate(licenseKey: licenseKey, identifier: deviceId);
      } finally {
        client.dispose();
      }
    }
    await clear();
    return true;
  }

  // ---------------- 内部 ----------------

  static LicenseState _stateFromClaims(
    LicenseState base,
    KeygateClaims claims, {
    Map<String, dynamic>? serverData,
  }) {
    return base.copyWith(
      tier: _tierOf(claims, serverData),
      expiresAt: claims.licenseEnd,
      checkInAt: claims.checkInAt,
      planName: _planNameOf(serverData, claims),
      licenseId: claims.licenseId,
      features: _featuresOf(serverData, claims),
    );
  }

  /// 套餐展示名优先取 verify/activate 响应里的 `plan_name`：
  /// token 里的 `pln` 在部分部署（含本项目的自建实例）是套餐 ID，不适合直接展示。
  static String _planNameOf(
    Map<String, dynamic>? serverData,
    KeygateClaims claims,
  ) {
    final name = serverData?['plan_name'];
    if (name is String && name.trim().isNotEmpty) {
      return name.trim();
    }
    return claims.planName;
  }

  /// 功能清单优先取响应里的 `features`，为空再退回 token 的 `ftr`。
  static Map<String, dynamic> _featuresOf(
    Map<String, dynamic>? serverData,
    KeygateClaims claims,
  ) {
    final features = serverData?['features'];
    if (features is Map && features.isNotEmpty) {
      return features.cast<String, dynamic>();
    }
    return claims.features;
  }

  static LicenseTier _tierOf(KeygateClaims claims,
      [Map<String, dynamic>? serverData]) {
    return switch (guessTier(
      planName: _planNameOf(serverData, claims),
      features: _featuresOf(serverData, claims),
    )) {
      LicenseTierGuess.pro => LicenseTier.pro,
      LicenseTierGuess.standard => LicenseTier.standard,
      LicenseTierGuess.free => LicenseTier.free,
    };
  }

  static String _messageKeyOf(KeygateResult result) {
    return switch (result.errorCode) {
      KeygateErrorCode.notFound => 'settingsLicenseErrorNotFound',
      KeygateErrorCode.activationLimit => 'settingsLicenseErrorLimit',
      KeygateErrorCode.expired => 'settingsLicenseErrorExpired',
      KeygateErrorCode.suspended => 'settingsLicenseErrorSuspended',
      KeygateErrorCode.lockedOut => 'settingsLicenseErrorLocked',
      KeygateErrorCode.network => 'settingsLicenseErrorNetwork',
      KeygateErrorCode.notConfigured => 'settingsLicenseServiceNotConfigured',
      KeygateErrorCode.serverError || null => 'settingsLicenseActivateFailed',
    };
  }

  static String _deviceLabel() {
    final os = Platform.operatingSystem;
    final name = os == 'windows'
        ? 'Windows PC'
        : os == 'macos'
        ? 'Mac'
        : os == 'linux'
        ? 'Linux PC'
        : os;
    final host = _hostName();
    return host == null || host.isEmpty ? name : '$name · $host';
  }

  static String? _hostName() {
    try {
      return Platform.localHostname.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(LicenseState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(state.toJson()));
  }
}
