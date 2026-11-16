// 职责: 调用自托管 Keygate 许可服务的三个客户端接口（activate / verify / deactivate）。
//   - 不需要任何 API Key：用户输入的授权码就是凭证。
//   - 网络失败、服务端错误码统一归一为 KeygateErrorCode，交给 UI 映射文案。
// 关联文件:
//   lib/shared/models/license.dart          （kKeygateBaseUrl）
//   lib/shared/services/keygate/keygate_token.dart
//   lib/shared/services/license_service.dart
//
// 接口约定（Keygate /api/v1/license）:
//   POST activate   {license_key, identifier, identifier_type?, label?} → {status, license_id, token}
//   POST verify     {license_key, identifier} → {status, plan_id, plan_name, valid_until?, features, grace_days, token}
//   POST deactivate {license_key, identifier}
//   GET  pubkey     → {algorithm, format, public_key}
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 客户端可识别的授权错误分类。
enum KeygateErrorCode {
  /// 授权码不存在 / 已失效 / 不属于本机（服务端统一返回 404）。
  notFound,

  /// 设备名额已满。
  activationLimit,

  /// 授权已过期。
  expired,

  /// 授权被暂停 / 吊销 / 取消。
  suspended,

  /// 尝试过于频繁，被临时锁定。
  lockedOut,

  /// 网络不可达或超时（可离线宽限）。
  network,

  /// 服务端 5xx 或响应格式异常。
  serverError,

  /// 本地配置缺失（未配置服务器地址或公钥）。
  notConfigured,
}

/// 单次调用结果。
class KeygateResult {
  const KeygateResult({
    required this.success,
    this.token,
    this.data = const <String, dynamic>{},
    this.errorCode,
    this.errorMessage,
    this.currentDevices,
    this.maxDevices,
  });

  const KeygateResult.failure(
    KeygateErrorCode code, {
    String? message,
    int? currentDevices,
    int? maxDevices,
  }) : success = false,
       token = null,
       data = const <String, dynamic>{},
       errorCode = code,
       errorMessage = message,
       currentDevices = currentDevices,
       maxDevices = maxDevices;

  final bool success;
  final String? token;
  final Map<String, dynamic> data;
  final KeygateErrorCode? errorCode;
  final String? errorMessage;
  final int? currentDevices;
  final int? maxDevices;
}

/// Keygate 许可服务 HTTP 客户端。
class KeygateClient {
  KeygateClient({
    required String baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
       _http = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _http;
  final Duration timeout;

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<KeygateResult> activate({
    required String licenseKey,
    required String identifier,
    String? label,
  }) {
    return _post('/api/v1/license/activate', <String, dynamic>{
      'license_key': licenseKey,
      'identifier': identifier,
      'identifier_type': 'device',
      if (label != null && label.isNotEmpty) 'label': label,
    });
  }

  Future<KeygateResult> verify({
    required String licenseKey,
    required String identifier,
  }) {
    return _post('/api/v1/license/verify', <String, dynamic>{
      'license_key': licenseKey,
      'identifier': identifier,
    });
  }

  Future<KeygateResult> deactivate({
    required String licenseKey,
    required String identifier,
  }) {
    return _post('/api/v1/license/deactivate', <String, dynamic>{
      'license_key': licenseKey,
      'identifier': identifier,
    });
  }

  Future<KeygateResult> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (!isConfigured) {
      return const KeygateResult.failure(KeygateErrorCode.notConfigured);
    }
    final uri = Uri.tryParse('$_baseUrl$path');
    if (uri == null) {
      return const KeygateResult.failure(KeygateErrorCode.notConfigured);
    }

    http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (error) {
      // 超时、DNS 失败、连接被重置都归到"网络不可达"，由上层走离线宽限。
      return KeygateResult.failure(
        KeygateErrorCode.network,
        message: error.toString(),
      );
    }

    Map<String, dynamic> json = const <String, dynamic>{};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        json = decoded.cast<String, dynamic>();
      }
    } catch (_) {
      json = const <String, dynamic>{};
    }

    final success = json['success'] == true;
    if (success) {
      final dataRaw = json['data'];
      final data = dataRaw is Map
          ? dataRaw.cast<String, dynamic>()
          : const <String, dynamic>{};
      final token = data['token'] as String?;
      return KeygateResult(success: true, token: token, data: data);
    }

    final code = _extractCode(json);
    final details = json['details'];
    int? current;
    int? max;
    if (details is Map) {
      final c = details['current'];
      final m = details['max'];
      if (c is num) {
        current = c.toInt();
      }
      if (m is num) {
        max = m.toInt();
      }
    }
    return KeygateResult.failure(
      _classify(response.statusCode, code),
      message: _extractMessage(json),
      currentDevices: current,
      maxDevices: max,
    );
  }

  /// 服务端错误码可能位于 `error.code`、`code` 或 `error`（字符串）。
  String _extractCode(Map<String, dynamic> json) {
    final error = json['error'];
    if (error is Map) {
      final code = error['code'];
      if (code is String && code.isNotEmpty) {
        return code.toUpperCase();
      }
    }
    if (error is String && error.isNotEmpty) {
      return error.toUpperCase();
    }
    final code = json['code'];
    if (code is String && code.isNotEmpty) {
      return code.toUpperCase();
    }
    return '';
  }

  String? _extractMessage(Map<String, dynamic> json) {
    final error = json['error'];
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    final message = json['message'];
    if (message is String && message.isNotEmpty) {
      return message;
    }
    return null;
  }

  KeygateErrorCode _classify(int statusCode, String code) {
    switch (code) {
      case 'ACTIVATION_LIMIT':
      case 'DEVICE_HELD':
        return KeygateErrorCode.activationLimit;
      case 'LICENSE_EXPIRED':
        return KeygateErrorCode.expired;
      case 'LICENSE_SUSPENDED':
      case 'LICENSE_REVOKED':
      case 'LICENSE_CANCELED':
      case 'SEAT_PAUSED':
        return KeygateErrorCode.suspended;
      case 'LICENSE_NOT_FOUND':
        return KeygateErrorCode.notFound;
      case 'LOCKED_OUT':
        return KeygateErrorCode.lockedOut;
    }
    if (statusCode == 404) {
      return KeygateErrorCode.notFound;
    }
    if (statusCode == 409) {
      return KeygateErrorCode.activationLimit;
    }
    if (statusCode == 429) {
      return KeygateErrorCode.lockedOut;
    }
    if (statusCode == 403) {
      return KeygateErrorCode.suspended;
    }
    return KeygateErrorCode.serverError;
  }

  void dispose() {
    _http.close();
  }
}
