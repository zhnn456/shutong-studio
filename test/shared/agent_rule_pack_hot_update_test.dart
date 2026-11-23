// 职责: 校验规则库热更链路——清单校验、缓存优先、校验失败回退内置、远端安装落地。
// 关联文件:
//   lib/shared/services/agent_rule_pack_service.dart
//   lib/shared/models/agent_rule_pack_manifest.dart
//   assets/rule_packs/manifest.json
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reveric/shared/models/agent_rule_pack.dart';
import 'package:reveric/shared/models/agent_rule_pack_manifest.dart';
import 'package:reveric/shared/services/agent_rule_pack_service.dart';

/// 用内存 map 冒充 assets：键是资源路径。
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) {
      throw FormatException('asset not found: $key');
    }
    final bytes = utf8.encode(text);
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final text = files[key];
    if (text == null) {
      throw FormatException('asset not found: $key');
    }
    return text;
  }
}

/// 按 URL 返回字节的 Dio 适配器，用于免网络的下载测试。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responses);

  final Map<String, List<int>> responses;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = responses[options.uri.toString()];
    if (body == null) {
      return ResponseBody.fromString('not found', 404);
    }
    return ResponseBody.fromBytes(body, 200);
  }

  @override
  void close({bool force = false}) {}
}

String _packFileJson(String packId) => jsonEncode({
  'version': 2,
  'packs': [
    {
      'id': packId,
      'name': packId,
      'summary': '',
      'category': '推理',
      'rules': [
        {'name': '$packId-1', 'content': '约束一'},
        {'name': '$packId-2', 'content': '约束二'},
      ],
    },
  ],
});

String _manifestJson({
  required int version,
  required Map<String, String> contents,
}) {
  final files = <Map<String, dynamic>>[];
  contents.forEach((name, text) {
    final bytes = utf8.encode(text);
    files.add({
      'file': name,
      'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    });
  });
  return jsonEncode({
    'schema': AgentRulePackManifest.supportedSchema,
    'version': version,
    'builtAt': '2026-11-23',
    'files': files,
  });
}

Future<Directory> _tempCacheDir() async {
  final dir = await Directory.systemTemp.createTemp('rule_pack_cache_test');
  addTearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });
  return dir;
}

Future<void> _writeCache(
  Directory dir, {
  required int version,
  required Map<String, String> contents,
}) async {
  await dir.create(recursive: true);
  for (final entry in contents.entries) {
    await File(p.join(dir.path, entry.key)).writeAsString(entry.value);
  }
  await File(
    p.join(dir.path, rulePackManifestFileName),
  ).writeAsString(_manifestJson(version: version, contents: contents));
}

_FakeBundle _bundle({int version = 5, String packId = 'bundled_pack'}) {
  final content = _packFileJson(packId);
  return _FakeBundle({
    rulePackAssetManifestPath: _manifestJson(
      version: version,
      contents: {'rule_packs.json': content},
    ),
    'assets/rule_packs/rule_packs.json': content,
  });
}

List<String> _ids(List<AgentRulePack> packs) =>
    packs.map((pack) => pack.id).toList(growable: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('没有热更缓存时使用内置资源', () async {
    final dir = await _tempCacheDir();
    final packs = await loadAgentRulePacks(
      refresh: true,
      bundle: _bundle(),
      cacheDirectory: () async => dir,
    );
    expect(_ids(packs), ['bundled_pack']);
  });

  test('缓存版本高于内置时优先热更内容', () async {
    final dir = await _tempCacheDir();
    await _writeCache(
      dir,
      version: 6,
      contents: {'hot.json': _packFileJson('hot_pack')},
    );
    final packs = await loadAgentRulePacks(
      refresh: true,
      bundle: _bundle(version: 5),
      cacheDirectory: () async => dir,
    );
    expect(_ids(packs), ['hot_pack']);
  });

  test('缓存版本不高于内置时仍用内置', () async {
    final dir = await _tempCacheDir();
    await _writeCache(
      dir,
      version: 5,
      contents: {'hot.json': _packFileJson('hot_pack')},
    );
    final packs = await loadAgentRulePacks(
      refresh: true,
      bundle: _bundle(version: 5),
      cacheDirectory: () async => dir,
    );
    expect(_ids(packs), ['bundled_pack']);
  });

  test('缓存文件被改动导致校验失败时回退内置', () async {
    final dir = await _tempCacheDir();
    await _writeCache(
      dir,
      version: 6,
      contents: {'hot.json': _packFileJson('hot_pack')},
    );
    // 篡改内容但不改清单里的 sha256。
    await File(
      p.join(dir.path, 'hot.json'),
    ).writeAsString(_packFileJson('tampered_pack'));
    final packs = await loadAgentRulePacks(
      refresh: true,
      bundle: _bundle(),
      cacheDirectory: () async => dir,
    );
    expect(_ids(packs), ['bundled_pack']);
  });

  test('清单拒绝路径穿越与非法 sha256', () {
    expect(
      () => AgentRulePackManifest.fromJson({
        'schema': 1,
        'version': 3,
        'files': [
          {'file': '../evil.json', 'bytes': 10, 'sha256': 'a' * 64},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => AgentRulePackManifest.fromJson({
        'schema': 1,
        'version': 3,
        'files': [
          {'file': 'ok.json', 'bytes': 10, 'sha256': 'zz'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => AgentRulePackManifest.fromJson({
        'schema': 99,
        'version': 3,
        'files': [
          {'file': 'ok.json', 'bytes': 10, 'sha256': 'a' * 64},
        ],
      }),
      throwsFormatException,
    );
  });

  test('refreshAgentRulePacks 下载校验后写入缓存并立即生效', () async {
    final dir = await _tempCacheDir();
    final manifestUrl = 'https://example.com/rule_packs/manifest.json';
    const fileUrl = 'https://example.com/rule_packs/hot.json';
    final hotContent = _packFileJson('remote_pack');
    final manifestText = _manifestJson(
      version: 7,
      contents: {'hot.json': hotContent},
    );

    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter({
        manifestUrl: utf8.encode(manifestText),
        fileUrl: utf8.encode(hotContent),
      });
    addTearDown(() => dio.close(force: true));

    final result = await refreshAgentRulePacks(
      manifestUrl: manifestUrl,
      client: dio,
      bundle: _bundle(version: 5),
      cacheDirectory: () async => dir,
    );

    expect(result.outcome, AgentRulePackUpdateOutcome.updated);
    expect(result.version, 7);
    expect(
      await File(p.join(dir.path, 'hot.json')).exists(),
      isTrue,
      reason: '校验通过的数据文件应落到缓存目录',
    );

    final packs = await loadAgentRulePacks(
      refresh: true,
      bundle: _bundle(version: 5),
      cacheDirectory: () async => dir,
    );
    expect(_ids(packs), ['remote_pack']);
  });

  test('refreshAgentRulePacks 版本没变时报告已是最新', () async {
    final dir = await _tempCacheDir();
    final manifestUrl = 'https://example.com/rule_packs/manifest.json';
    final manifestText = _manifestJson(
      version: 5,
      contents: {'rule_packs.json': _packFileJson('bundled_pack')},
    );
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter({
        manifestUrl: utf8.encode(manifestText),
      });
    addTearDown(() => dio.close(force: true));

    final result = await refreshAgentRulePacks(
      manifestUrl: manifestUrl,
      client: dio,
      bundle: _bundle(version: 5),
      cacheDirectory: () async => dir,
    );
    expect(result.outcome, AgentRulePackUpdateOutcome.latest);
  });

  test('refreshAgentRulePacks 校验失败时不污染已有缓存', () async {
    final dir = await _tempCacheDir();
    await _writeCache(
      dir,
      version: 6,
      contents: {'hot.json': _packFileJson('hot_pack')},
    );
    final manifestUrl = 'https://example.com/rule_packs/manifest.json';
    final badContent = _packFileJson('broken_pack');
    final manifestText = _manifestJson(
      version: 8,
      contents: {'hot.json': badContent},
    );
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter({
        manifestUrl: utf8.encode(manifestText),
        // 返回与清单不一致的内容，触发 sha256 校验失败。
        'https://example.com/rule_packs/hot.json': utf8.encode(
          _packFileJson('other_pack'),
        ),
      });
    addTearDown(() => dio.close(force: true));

    final result = await refreshAgentRulePacks(
      manifestUrl: manifestUrl,
      client: dio,
      bundle: _bundle(version: 5),
      cacheDirectory: () async => dir,
    );
    expect(result.isFailed, isTrue);

    // 旧缓存仍在，且仍被优先使用。
    final packs = await loadAgentRulePacks(
      refresh: true,
      bundle: _bundle(version: 5),
      cacheDirectory: () async => dir,
    );
    expect(_ids(packs), ['hot_pack']);
  });

  test('resetAgentRulePacksToBundled 清空缓存后回到内置', () async {
    final dir = await _tempCacheDir();
    await _writeCache(
      dir,
      version: 6,
      contents: {'hot.json': _packFileJson('hot_pack')},
    );
    await resetAgentRulePacksToBundled(cacheDirectory: () async => dir);
    final packs = await loadAgentRulePacks(
      refresh: true,
      bundle: _bundle(version: 5),
      cacheDirectory: () async => dir,
    );
    expect(_ids(packs), ['bundled_pack']);
  });
}
