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

  /// 提交客服留言到 Keygate 后台（匿名，无需授权码）。
  /// 服务端约定：`POST /api/v1/feedback`，返回 `{success: true, data: {id}}`。
  /// [type] 必须是服务端白名单值：suggestion / bug / feedback（由上层映射）。
  /// [deviceId] 为本机稳定标识，用于后台回溯与客户端拉回回复；
  /// [licenseKeyHash] 为授权码的 SHA-256 hex（明文授权码不上传），可为空。
  Future<KeygateResult> submitFeedback({
    required String type,
    required String content,
    String? contact,
    String? deviceId,
    String? licenseKeyHash,
    String? appVersion,
    String? os,
    String? product,
    String? productName,
  }) {
    return _post('/api/v1/feedback', <String, dynamic>{
      'type': type,
      'content': content,
      'source': 'desktop',
      if (contact != null && contact.trim().isNotEmpty)
        'contact': contact.trim(),
      if (deviceId != null && deviceId.trim().isNotEmpty)
        'device_id': deviceId.trim(),
      if (licenseKeyHash != null && licenseKeyHash.trim().isNotEmpty)
        'license_key_hash': licenseKeyHash.trim(),
      if (appVersion != null && appVersion.trim().isNotEmpty)
        'app_version': appVersion.trim(),
      if (os != null && os.trim().isNotEmpty) 'os': os.trim(),
      // 产品标识：后台据此区分鲸喜AI / 书童AI写作 / 后续其他产品。
      if (product != null && product.trim().isNotEmpty)
        'product': product.trim(),
      if (productName != null && productName.trim().isNotEmpty)
        'product_name': productName.trim(),
    });
  }

  /// 拉取本机已收到回复的留言：`GET /api/v1/feedback/check?device_id=…`。
  /// 仅返回状态为 replied、回复非空的条目；未回复的不回传，避免噪音。
  Future<KeygateResult> fetchFeedbackReplies(String deviceId) {
    return _get('/api/v1/feedback/check', query: <String, String>{
      'device_id': deviceId,
    });
  }

  /// 拉取本机完整留言会话：`GET /api/v1/feedback?device_id=…`。
  Future<KeygateResult> fetchFeedbackThread(String deviceId) {
    return _get('/api/v1/feedback', query: <String, String>{
      'device_id': deviceId,
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

  Future<KeygateResult> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    if (!isConfigured) {
      return const KeygateResult.failure(KeygateErrorCode.notConfigured);
    }
    var uri = Uri.tryParse('$_baseUrl$path');
    if (uri == null) {
      return const KeygateResult.failure(KeygateErrorCode.notConfigured);
    }
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }

    http.Response response;
    try {
      response = await _http
          .get(
            uri,
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(timeout);
    } catch (error) {
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

    if (json['success'] == true) {
      final dataRaw = json['data'];
      final data = dataRaw is Map
          ? dataRaw.cast<String, dynamic>()
          : const <String, dynamic>{};
      return KeygateResult(success: true, data: data);
    }
    return KeygateResult.failure(
      _classify(response.statusCode, _extractCode(json)),
      message: _extractMessage(json),
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
