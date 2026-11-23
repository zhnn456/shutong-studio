// 职责: 获取 New API 模型目录，并按模型名路由聊天协议、装配各类生成客户端。
// 关联文件:
//   lib/shared/models/new_api.dart
//   lib/shared/services/ai/provider_initializer.dart
//   lib/shared/services/ai/image/new_api.dart
//   lib/shared/services/ai/audio/gemini.dart
//   lib/shared/services/ai/video/new_api.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../agent/client.dart';
import '../../agent/client/openai_client.dart';
import '../../agent/client/openai_responses_client.dart';
import '../../agent/client/anthropic_client.dart';
import '../../agent/client/gemini_client.dart';
import '../../agent/client/trace_headers_http_client.dart';
import '../../logger/app_logger.dart';
import '../../models/ai_provider.dart';
import '../../models/new_api.dart';
import '../../models/models_catalog.dart';
import '../../models/audio/channels.dart';
import '../../models/audio/catalog.dart';
import '../../models/image/channels.dart';
import '../../models/video/channels.dart';
import '../../models/video/catalog.dart';
import 'media_diagnostics.dart';
import 'image/new_api.dart';
import 'audio/client.dart';
import 'audio/gemini.dart';
import 'audio/new_api.dart';
import 'video/new_api.dart';

final _log = AppLogger.forModule('NewApiModels');

/// 只有"根本没拿到响应"才算连不上；HTTP 4xx/5xx 都说明域名是通的。
bool _isConnectionFailure(Object error) =>
    error is http.ClientException ||
    error is SocketException ||
    error is TimeoutException;

/// 聚合网关（New API / One API 等）的 /v1/models 一般不带模态元数据，
/// 图像模型只能从型号名识别。只依赖端点类型时，「获取模型」的图像列表
/// 会只剩 `mj_imagine` 一条，所以这里补一层主流图像型号族的名称匹配。
bool isGatewayImageModel(String modelId) {
  final name = modelId.toLowerCase();
  final segments = name.split(RegExp(r'[^a-z0-9]+'));
  const segmentMarkers = {
    'image',
    'images',
    'imagine',
    'midjourney',
    'mj',
    'imagen',
    'ideogram',
    'flux',
    'dalle',
    'seedream',
    'seededit',
    'recraft',
    'banana',
  };
  if (segments.any(segmentMarkers.contains)) {
    return true;
  }
  const prefixes = [
    'mj-',
    'dall-e',
    'gpt-image',
    'stable-diffusion',
    'sdxl',
    'sd3',
    'nano-banana',
    'banana-',
    'qwen-image',
    'wanx',
    'kolors',
    'grok-image',
    'doubao-seedream',
  ];
  return prefixes.any(name.startsWith);
}

/// New API 网关返回非 200 时抛出。
/// 以前这里抛的是 StateError，设置页只认带状态码的异常类型，于是 401
/// 「无效的令牌」也被显示成「服务端内部错误」，把人引到错的方向。
class NewApiRequestException implements Exception {
  const NewApiRequestException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// 星辰AI：先探一次主域名是否连得上；连不上就切到写死的备用域名。
///
/// 备用域名不展示、不可配置，只在主域名连不上时生效。探测只看"连不上"
/// （连接失败、超时、DNS 失败），401/404 这类有 HTTP 响应的算主域名正常。
Future<void> probeApi88BaseUrl(AiProvider config, {http.Client? httpClient}) async {
  if (config.typeEnum != AiProviderType.api88) {
    return;
  }
  final client = httpClient ?? http.Client();
  try {
    final request =
        http.Request('GET', Uri.parse('$api88PrimaryBaseUrl/models'))
          ..followRedirects = false;
    final response = await (() async => http.Response.fromStream(
      await client.send(request),
    ))().timeout(const Duration(seconds: 6));
    _log.debug('api88 probe status=${response.statusCode}');
    // 主域名有响应就回到主域名（备用域名只在主域名连不上时使用）。
    resetApi88BaseUrl();
  } catch (error) {
    if (_isConnectionFailure(error)) {
      markApi88BaseUrlFallback();
      _log.warning('星辰AI 主域名连不上，切到备用域名：$error');
    }
  } finally {
    if (httpClient == null) {
      client.close();
    }
  }
}

class NewApiClient {
  const NewApiClient(this.config);
  final AiProvider config;

  Future<List<NewApiModel>> models({http.Client? httpClient}) async {
    final endpoint = Uri.parse(config.effectiveBaseUrl);
    if (!{'http', 'https'}.contains(endpoint.scheme) ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        config.effectiveApiKey.trim().isEmpty) {
      throw StateError('New API requires a valid base URL and API key');
    }
    final uri = endpoint.replace(path: '${endpoint.path}/models');
    final transport = httpClient ?? config.createProxyClient() ?? http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['Authorization'] = 'Bearer ${config.effectiveApiKey}';
      final response = await (() async => http.Response.fromStream(
        await transport.send(request),
      ))().timeout(const Duration(seconds: 30));
      if (_log.isDebugEnabled) {
        _log.debug(
          'GET $uri status=${response.statusCode} body=${response.body}',
        );
      }
      if (response.statusCode != 200) {
        throw NewApiRequestException(
          statusCode: response.statusCode,
          message:
              'GET ${uri.origin}${uri.path}: HTTP ${response.statusCode} '
              '${safeMediaDiagnostic(response.body, config.effectiveApiKey)}',
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (json['data'] as List)
          .map((item) => NewApiModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (error) {
      // 主域名连不上时切一次写死的备用域名再试；有 HTTP 响应的错误不重试。
      if (_isConnectionFailure(error) &&
          config.typeEnum == AiProviderType.api88 &&
          markApi88BaseUrlFallback()) {
        _log.warning('星辰AI 主域名连不上，改用备用域名重试：$error');
        if (httpClient == null) {
          transport.close();
        }
        return models(httpClient: httpClient);
      }
      _log.warning(
        'GET ${uri.origin}${uri.path} '
        'type=${error.runtimeType} message=${safeMediaDiagnostic(error, config.effectiveApiKey)}',
      );
      rethrow;
    } finally {
      if (httpClient == null) {
        transport.close();
      }
    }
  }

  Future<List<String>> modelIds(AiModelKind kind) async {
    final list = await models();
    return (list
        .where((model) {
          final imageByName = isGatewayImageModel(model.id);
          final image =
              imageByName ||
              lookupImageChannelModel(config.type, model.id) != null;
          final audio = lookupAudioChannelModel(config.type, model.id) != null;
          final video =
              isNewApiVideoModel(model.id) ||
              lookupVideoChannelModel(config.type, model.id) != null ||
              model.endpointTypes.contains('openai-video') ||
              model.endpointTypes.contains('video-generation');
          return switch (kind) {
            AiModelKind.image =>
              model.id == 'mj_imagine' ||
                  imageByName ||
                  model.endpointTypes.contains('image-generation') ||
                  model.endpointTypes.contains('image-edit') ||
                  (model.endpointTypes.contains('gemini') && !audio && !video),
            AiModelKind.audio =>
              audio &&
                  model.endpointTypes.contains(
                    lookupAudioChannelModel(
                          config.type,
                          model.id,
                        )!.catalogId.contains('gemini-')
                        ? 'gemini'
                        : 'openai',
                  ),
            AiModelKind.video => video,
            AiModelKind.chat =>
              !image &&
                  !audio &&
                  !video &&
                  lookupImageModel(model.id) == null &&
                  lookupAudioModel(model.id) == null &&
                  !audioChannelModels[AudioProtocol.new_api_speech]!
                      .containsKey(model.id) &&
                  lookupVideoModel(model.id) == null &&
                  !model.endpointTypes.contains('image-generation') &&
                  !model.endpointTypes.contains('image-edit') &&
                  !model.endpointTypes.contains('openai-video') &&
                  !model.endpointTypes.contains('video-generation') &&
                  (model.endpointTypes.isEmpty ||
                      model.endpointTypes.any(
                        {
                          'openai',
                          'openai-response',
                          'anthropic',
                          'gemini',
                        }.contains,
                      )),
            // 语音转写模型来自供应商侧配置的 asrModels，不在网关模型目录里筛选。
            AiModelKind.asr => false,
          };
        })
        .map((model) => model.id)
        .toSet()
        .toList()
      ..sort());
  }

  Future<ProviderClient> chat({
    required String model,
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
    TraceHeadersProvider? traceHeadersProvider,
    String? cacheKeyUserId,
  }) async {
    final root = config.effectiveBaseUrl.replaceFirst(RegExp(r'/v1$'), '');
    return switch (NewApiChatProtocol.forModel(model)) {
      NewApiChatProtocol.responses => OpenAIResponsesClient(
        apiKey: config.effectiveApiKey,
        baseUrl: config.effectiveBaseUrl,
        model: model,
        httpClient: httpClient,
        streamHttpClientFactory: streamClientFactory,
        traceHeadersProvider: traceHeadersProvider,
      ),
      NewApiChatProtocol.anthropic => AnthropicClient(
        apiKey: config.effectiveApiKey,
        baseUrl: root,
        model: model,
        httpClient: httpClient,
        streamHttpClientFactory: streamClientFactory,
        traceHeadersProvider: traceHeadersProvider,
        cacheKeyUserId: cacheKeyUserId,
      ),
      NewApiChatProtocol.gemini => GeminiClient(
        apiKey: config.effectiveApiKey,
        baseUrl: root,
        model: model,
        httpClient: httpClient,
        authAsHeader: true,
        streamHttpClientFactory: streamClientFactory,
        traceHeadersProvider: traceHeadersProvider,
      ),
      NewApiChatProtocol.openai => OpenAiClient(
        apiKey: config.effectiveApiKey,
        baseUrl: config.effectiveBaseUrl,
        model: model,
        httpClient: httpClient,
        streamClientFactory: streamClientFactory,
        traceHeadersProvider: traceHeadersProvider,
        useThinkingField: useThinkingField(model),
      ),
    };
  }

  NewApiImageClient image() => NewApiImageClient(config);
  AudioClient audio(http.Client transport, String model) {
    final catalogId =
        lookupAudioChannelModel(config.type, model)?.catalogId ?? model;
    if (catalogId.contains('gemini-')) {
      return GeminiAudioClient(
        transport,
        config.effectiveApiKey,
        providerType: config.type,
        endpoint: Uri.parse(
          config.effectiveBaseUrl.replaceFirst(RegExp(r'/v1$'), ''),
        ),
      );
    }
    return NewApiAudioClient(
      transport,
      config.effectiveApiKey,
      providerType: config.type,
      endpoint: Uri.parse(config.effectiveBaseUrl),
    );
  }

  NewApiVideoClient video(http.Client transport) => NewApiVideoClient(
    httpClient: transport,
    providerType: config.type,
    apiKey: config.effectiveApiKey,
    endpoint: Uri.parse(config.effectiveBaseUrl),
  );
}
