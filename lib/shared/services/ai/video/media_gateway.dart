// 职责: 以星辰AI（lk888/lk666）媒体网关的异步协议提交并查询视频任务。
// 关联文件:
//   lib/shared/services/ai/video/client.dart
//   lib/shared/models/video/channels.dart
//   lib/shared/models/video/request.dart
//   lib/shared/models/video/task_result.dart
//
// 站点协议（GET /v1/skills 接口文档）:
//   - 提交: POST /v1/media/generate，body {model, prompt, params:{...}}，
//     响应 data.task_id 为任务 ID；
//   - 轮询: GET /v1/skills/task-status?task_id=xxx（原版 /v1/media/status 仍可用），
//     终态字段 is_final / status_group / state / result_url / error。
import '../../../models/video/channels.dart';
import '../../../models/video/request.dart';
import '../../../models/video/task_result.dart';
import 'client.dart';

class MediaGatewayVideoClient extends VideoClient {
  MediaGatewayVideoClient({
    required super.httpClient,
    required super.providerType,
    required super.endpoint,
    required super.apiKey,
    super.timeout,
    this.submitTimeout = const Duration(minutes: 3),
  });

  @override
  final Duration submitTimeout;

  @override
  String get createPath => 'media/generate';

  @override
  String queryPath(String id) => 'skills/task-status';

  @override
  Uri queryUrl(String id, String modelId) =>
      url(queryPath(id)).replace(queryParameters: {'task_id': id});

  @override
  Map<String, dynamic> encode(
    VideoRequest request,
    List<VideoReference> references,
  ) {
    if (request.prompt.trim().isEmpty || request.durationSeconds <= 0) {
      throw const VideoException(
        VideoErrorCode.invalid_request,
        field: 'prompt',
      );
    }
    // 站点按系列使用不同字段名（Seedance: aspect_ratio / 万相: ratio），
    // 并有个别系列级必填项（万相: version）。字段差异登记在渠道层，这里读取。
    final options = switch (lookupVideoChannelModel(
      providerType,
      request.modelId,
    )?.protocolOptions) {
      final MediaGatewayVideoOptions options => options,
      _ => const MediaGatewayVideoOptions(),
    };
    final params = <String, dynamic>{...options.fixedParams};
    params['duration'] = request.durationSeconds.toString();
    params['resolution'] = request.resolution;
    if (options.sendsRatio) {
      params[options.ratioField] = request.ratio;
    }

    switch (request.mode) {
      case VideoMode.text:
        break;
      case VideoMode.first_frame:
      case VideoMode.first_last_frame:
        params['mode'] = 'shouweizhen';
        final frames = <String>[
          for (final ref in references)
            if (ref.role == VideoInputRole.first_frame) ref.url,
          for (final ref in references)
            if (ref.role == VideoInputRole.last_frame) ref.url,
        ];
        if (frames.isNotEmpty) {
          params[options.frameImagesField] = frames;
        }
      case VideoMode.reference:
        params['mode'] = 'cankaosheng';
        final images = references
            .where((ref) => ref.role.kind == VideoMediaKind.image)
            .map((ref) => ref.url)
            .toList();
        final videos = references
            .where((ref) => ref.role.kind == VideoMediaKind.video)
            .map((ref) => ref.url)
            .toList();
        final audios = references
            .where((ref) => ref.role.kind == VideoMediaKind.audio)
            .map((ref) => ref.url)
            .toList();
        if (images.isNotEmpty) params[options.referenceImageField] = images;
        if (videos.isNotEmpty) params[options.referenceVideoField] = videos;
        if (audios.isNotEmpty) params[options.referenceAudioField] = audios;
    }

    return {
      'model': request.modelId,
      'prompt': request.prompt,
      'params': params,
    };
  }

  @override
  String submissionId(Map<String, dynamic> json) {
    final data = json['data'];
    final raw = data is Map ? data['task_id'] : json['task_id'];
    final id = raw?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const FormatException('Missing task ID');
    }
    return id;
  }

  @override
  VideoTaskResult decodeResult(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final statusGroup = (data['status_group'] as String? ?? '').trim();
    final state = (data['state'] as String? ?? '').trim().toLowerCase();
    final status = (data['status'] as String? ?? '').trim().toLowerCase();
    final resultUrl = data['result_url'] as String?;
    final rawError = data['error'];
    final error = rawError is String ? rawError.trim() : '';

    final statusKind = switch (state) {
      'success' => VideoRemoteStatus.succeeded,
      'failed' => VideoRemoteStatus.failed,
      'cancelled' || 'canceled' => VideoRemoteStatus.cancelled,
      'expired' => VideoRemoteStatus.expired,
      _ => switch (statusGroup) {
          '已完成' => VideoRemoteStatus.succeeded,
          '失败' => VideoRemoteStatus.failed,
          '等待中' => VideoRemoteStatus.queued,
          '处理中' => VideoRemoteStatus.running,
          _ => _decodeStatus(status, error),
        },
    };

    Uri? videoUrl;
    if (statusKind == VideoRemoteStatus.succeeded) {
      if (resultUrl == null || resultUrl.trim().isEmpty) {
        throw const FormatException('Missing video URL');
      }
      videoUrl = Uri.parse(resultUrl.trim());
      if (!{'http', 'https'}.contains(videoUrl.scheme) ||
          videoUrl.host.isEmpty ||
          videoUrl.userInfo.isNotEmpty) {
        throw const FormatException('Missing video URL');
      }
    }
    return VideoTaskResult(status: statusKind, videoUrl: videoUrl);
  }

  VideoRemoteStatus _decodeStatus(String status, String error) {
    if (status == 'completed' || status == 'succeeded') {
      return VideoRemoteStatus.succeeded;
    }
    if (status == 'failed' || status == 'error' || error.isNotEmpty) {
      return VideoRemoteStatus.failed;
    }
    if (status == 'cancelled' || status == 'canceled') {
      return VideoRemoteStatus.cancelled;
    }
    if (status == 'expired') {
      return VideoRemoteStatus.expired;
    }
    if (status == 'queued' ||
        status == 'pending' ||
        status.contains('排队') ||
        status.contains('等待')) {
      return VideoRemoteStatus.queued;
    }
    if (status == 'in_progress' ||
        status == 'running' ||
        status.contains('生成') ||
        status.contains('处理')) {
      return VideoRemoteStatus.running;
    }
    return VideoRemoteStatus.unknown;
  }
}
