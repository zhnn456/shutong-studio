// 职责: 校验星辰AI（api88）媒体网关的 Seedance / 万相型号登记完整、
// 能力非空，且提交参数按列表的字段名与固定项组装。
// 关联文件:
//   lib/shared/models/video/channels.dart
//   lib/shared/services/ai/video/media_gateway.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:reveric/shared/models/video/channels.dart';
import 'package:reveric/shared/models/video/request.dart';
import 'package:reveric/shared/services/ai/video/media_gateway.dart';

const _provider = 'api88';

/// 供应商设置页「视频模型」里用户实际列出的 10 个型号，必须全部能解析到能力。
const _listedModels = [
  'doubao-seedance-2-5-260628',
  'doubao-seedance-2-5-cankaosheng',
  'doubao-seedance-2-5-quannengcankao',
  'doubao-seedance-2-5-shouweizhen',
  'minimax-h3',
  'wan3.0',
  'wan3.0-video',
  'wan3.0-video-cankaosheng',
  'wan3.0-video-quannengcankao',
  'wan3.0-video-shouweizhen',
];

MediaGatewayVideoClient _client() => MediaGatewayVideoClient(
  httpClient: http.Client(),
  providerType: _provider,
  endpoint: Uri.parse('https://api.lk888.ai/v1'),
  apiKey: 'test-key',
);

Map<String, dynamic> _params(Map<String, dynamic> body) =>
    Map<String, dynamic>.from(body['params'] as Map);

VideoReference _image(String url) => VideoReference(
  role: VideoInputRole.reference_image,
  url: url,
  mimeType: 'image/png',
  fileSize: 1,
  mediaInfo: const VideoMediaInfo(),
);

VideoReference _frame(String url) => VideoReference(
  role: VideoInputRole.first_frame,
  url: url,
  mimeType: 'image/png',
  fileSize: 1,
  mediaInfo: const VideoMediaInfo(),
);

void main() {
  group('星辰AI 视频型号登记', () {
    test('设置页列出的型号全部具备能力', () {
      for (final model in _listedModels) {
        final channel = lookupVideoChannelModel(_provider, model);
        expect(channel, isNotNull, reason: model);
        final caps = channel!.capabilities;
        expect(caps.modes, isNotEmpty, reason: '$model modes');
        expect(caps.resolutions, isNotEmpty, reason: '$model resolutions');
        expect(caps.ratios, isNotEmpty, reason: '$model ratios');
        expect(caps.durations, isNotEmpty, reason: '$model durations');
      }
    });

    test('渠道型号清单覆盖设置页型号', () {
      final keys = videoModelsForProvider(_provider);
      for (final model in _listedModels) {
        expect(keys, contains(model));
      }
    });

    test('参考生型号只接受参考模式并声明图片上限', () {
      final caps = lookupVideoChannelModel(
        _provider,
        'doubao-seedance-2-5-cankaosheng',
      )!.capabilities;
      expect(caps.modes, [VideoMode.reference]);
      expect(caps.references[VideoMediaKind.image]?.maxCount, 30);
      expect(caps.references[VideoMediaKind.video], isNull);
    });

    test('首尾帧型号不要求音频参数', () {
      final channel = lookupVideoChannelModel(
        _provider,
        'doubao-seedance-2-5-shouweizhen',
      )!;
      expect(channel.requestDefaults.audio, isNull);
      expect(
        channel.capabilities.modes,
        containsAll([VideoMode.first_frame, VideoMode.first_last_frame]),
      );
    });
  });

  group('提交参数组装', () {
    test('Seedance 2.5 文生发送 aspect_ratio / resolution / duration', () {
      final body = _client().encode(
        const VideoRequest(
          modelId: 'doubao-seedance-2-5-260628',
          prompt: '测试提示词',
          mode: VideoMode.text,
          resolution: '1080p',
          ratio: '16:9',
          durationSeconds: 6,
        ),
        const [],
      );
      final params = _params(body);
      expect(body['model'], 'doubao-seedance-2-5-260628');
      expect(params['aspect_ratio'], '16:9');
      expect(params['resolution'], '1080p');
      expect(params['duration'], '6');
      expect(params.containsKey('mode'), isFalse);
      expect(params.containsKey('images'), isFalse);
    });

    test('首尾帧型号按 images 顺序提交首帧与尾帧', () {
      final body = _client().encode(
        const VideoRequest(
          modelId: 'wan3.0-video-shouweizhen',
          prompt: '测试提示词',
          mode: VideoMode.first_last_frame,
          resolution: '720P',
          ratio: 'adaptive',
          durationSeconds: 5,
        ),
        [_frame('https://a/first.png')],
      );
      final params = _params(body);
      expect(params['mode'], 'shouweizhen');
      expect(params['images'], ['https://a/first.png']);
      expect(params.containsKey('ratio'), isFalse);
      expect(params['version'], 'standard');
    });

    test('万相参考生使用 reference_urls 并带必填版本', () {
      final body = _client().encode(
        const VideoRequest(
          modelId: 'wan3.0-video-cankaosheng',
          prompt: '测试提示词',
          mode: VideoMode.reference,
          resolution: '480P',
          ratio: '9:16',
          durationSeconds: 5,
        ),
        [_image('https://a/ref.png')],
      );
      final params = _params(body);
      expect(params['mode'], 'cankaosheng');
      expect(params['reference_urls'], ['https://a/ref.png']);
      expect(params.containsKey('image_url'), isFalse);
      expect(params['ratio'], '9:16');
      expect(params['aspect_ratio'], isNull);
      expect(params['version'], 'standard');
    });

    test('Seedance 全能参考分别提交图 / 视 / 音', () {
      final refs = <VideoReference>[
        _image('https://a/ref.png'),
        const VideoReference(
          role: VideoInputRole.reference_video,
          url: 'https://a/ref.mp4',
          mimeType: 'video/mp4',
          fileSize: 1,
          mediaInfo: VideoMediaInfo(),
        ),
        const VideoReference(
          role: VideoInputRole.reference_audio,
          url: 'https://a/ref.mp3',
          mimeType: 'audio/mpeg',
          fileSize: 1,
          mediaInfo: VideoMediaInfo(),
        ),
      ];
      final body = _client().encode(
        const VideoRequest(
          modelId: 'doubao-seedance-2-5-quannengcankao',
          prompt: '测试提示词',
          mode: VideoMode.reference,
          resolution: '720p',
          ratio: '1:1',
          durationSeconds: 5,
        ),
        refs,
      );
      final params = _params(body);
      expect(params['image_url'], ['https://a/ref.png']);
      expect(params['video_url'], ['https://a/ref.mp4']);
      expect(params['audio_url'], ['https://a/ref.mp3']);
      expect(params['aspect_ratio'], '1:1');
    });
  });
}
