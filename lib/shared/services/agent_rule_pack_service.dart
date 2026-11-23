// 职责: 加载规则包库（内置资源 + 远端热更缓存），并把选中的规则包写入作品内容库。
// 关联文件:
//   assets/rule_packs/rule_packs.json
//   assets/rule_packs/short_drama_packs.json
//   assets/rule_packs/manifest.json
//   lib/shared/models/agent_rule_pack.dart
//   lib/shared/models/agent_rule_pack_manifest.dart
//   lib/shared/app_config.dart
//   lib/shared/services/agent_rule_copy_service.dart
//   lib/desktop/widgets/agent_management/agent_rule_pack_dialog.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';
import '../database/novel_content_database.dart';
import '../logger/app_logger.dart';
import '../models/agent_rule_pack.dart';
import '../models/agent_rule_pack_manifest.dart';
import '../utils/random_id.dart';
import '../utils/storage_paths.dart';
import 'agent_rule_copy_service.dart';
import 'novel_content.dart';

final _log = AppLogger.forModule('AgentRulePack');

/// 内置规则包资源清单：小说题材包 + 竖屏短剧流派包，按顺序合并。
const List<String> rulePackAssetPaths = <String>[
  'assets/rule_packs/rule_packs.json',
  'assets/rule_packs/short_drama_packs.json',
];

/// 内置清单，只用于读出「内置版本号」，与热更缓存做新旧比较。
const String rulePackAssetManifestPath = 'assets/rule_packs/manifest.json';

/// 热更缓存目录（位于应用数据根目录下），存放 manifest.json 与数据文件。
const String rulePackCacheFolderName = 'rule_packs_cache';
const String rulePackManifestFileName = 'manifest.json';

/// 单个数据文件与清单的体积上限，防止异常响应把磁盘写满。
const int maxRulePackFileBytes = 4 * 1024 * 1024;
const int maxRulePackManifestBytes = 256 * 1024;

List<AgentRulePack>? _cache;
int _activeVersion = 0;
bool _activeIsHotUpdate = false;
String _activeBuiltAt = '';

/// 规则库当前状态，供设置页与规则库弹窗展示。
class AgentRulePackLibraryStatus {
  const AgentRulePackLibraryStatus({
    required this.version,
    required this.isHotUpdate,
    required this.packCount,
    required this.ruleCount,
    required this.builtAt,
  });

  final int version;
  final bool isHotUpdate;
  final int packCount;
  final int ruleCount;
  final String builtAt;
}

enum AgentRulePackUpdateOutcome { updated, latest, failed }

class AgentRulePackUpdateResult {
  const AgentRulePackUpdateResult({
    required this.outcome,
    required this.version,
    required this.message,
  });

  const AgentRulePackUpdateResult.failed(this.message)
    : outcome = AgentRulePackUpdateOutcome.failed,
      version = 0;

  final AgentRulePackUpdateOutcome outcome;
  final int version;
  final String message;

  bool get isFailed => outcome == AgentRulePackUpdateOutcome.failed;
}

/// 读取规则包库。优先使用本地热更缓存；缓存缺失或校验失败时回退内置资源。
///
/// [refresh] 为 true 时丢弃进程内缓存，重新按「缓存 > 内置」判定一次。
Future<List<AgentRulePack>> loadAgentRulePacks({
  bool refresh = false,
  AssetBundle? bundle,
  Future<Directory> Function()? cacheDirectory,
}) async {
  final cached = _cache;
  if (cached != null && !refresh) {
    return cached;
  }
  final loader = bundle ?? rootBundle;
  final bundledVersion = await _readManifestVersion(loader);
  final hot = await _loadCachedLibrary(
    await _resolveCacheDirectory(cacheDirectory),
    bundledVersion,
  );
  if (hot != null) {
    _activeVersion = hot.version;
    _activeIsHotUpdate = true;
    _activeBuiltAt = hot.builtAt;
    _cache = hot.packs;
    return hot.packs;
  }
  final bundled = await _loadBundledLibrary(loader);
  _activeVersion = bundledVersion;
  _activeIsHotUpdate = false;
  _activeBuiltAt = '';
  _cache = bundled;
  return bundled;
}

/// 当前规则库概况（版本、来源、包数与条数）。
Future<AgentRulePackLibraryStatus> describeAgentRulePackLibrary({
  AssetBundle? bundle,
  Future<Directory> Function()? cacheDirectory,
}) async {
  final packs = await loadAgentRulePacks(
    bundle: bundle,
    cacheDirectory: cacheDirectory,
  );
  return AgentRulePackLibraryStatus(
    version: _activeVersion,
    isHotUpdate: _activeIsHotUpdate,
    packCount: packs.length,
    ruleCount: packs.fold<int>(0, (sum, pack) => sum + pack.rules.length),
    builtAt: _activeBuiltAt,
  );
}

/// 从远端清单检查并安装规则库更新。
///
/// 成功条件：清单可解析、版本比当前新、每个文件字节数与 sha256 都校验通过。
/// 任何一步失败都不改动已有缓存，调用方继续使用当前规则库。
Future<AgentRulePackUpdateResult> refreshAgentRulePacks({
  String? manifestUrl,
  Dio? client,
  AssetBundle? bundle,
  Future<Directory> Function()? cacheDirectory,
}) async {
  final url = (manifestUrl ?? revericRulePackManifestUrl).trim();
  if (url.isEmpty) {
    return const AgentRulePackUpdateResult.failed('未配置规则库更新地址');
  }
  Dio? owned;
  final http = client ?? _createClient();
  if (client == null) {
    owned = http;
  }
  final cacheDir = await _resolveCacheDirectory(cacheDirectory);
  Directory? staging;
  try {
    final manifestBytes = await _download(http, url, maxRulePackManifestBytes);
    final decoded = jsonDecode(utf8.decode(manifestBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('规则库清单顶层不是对象');
    }
    final manifest = AgentRulePackManifest.fromJson(decoded);
    final current = await describeAgentRulePackLibrary(
      bundle: bundle,
      cacheDirectory: cacheDirectory,
    );
    if (!manifest.isNewerThan(
      AgentRulePackManifest(
        version: current.version,
        builtAt: current.builtAt,
        files: const [],
      ),
    )) {
      return AgentRulePackUpdateResult(
        outcome: AgentRulePackUpdateOutcome.latest,
        version: current.version,
        message: '',
      );
    }

    staging = Directory(
      p.join(cacheDir.path, 'staging_${DateTime.now().microsecondsSinceEpoch}'),
    );
    await staging.create(recursive: true);

    // 先全部下载并校验到临时目录，任一步失败都不污染现有缓存。
    for (final entry in manifest.files) {
      final bytes = await _download(
        http,
        _resolveFileUrl(url, entry.file),
        maxRulePackFileBytes,
      );
      if (bytes.length != entry.bytes) {
        throw FormatException('${entry.file} 字节数不符');
      }
      if (sha256.convert(bytes).toString() != entry.sha256) {
        throw FormatException('${entry.file} 校验失败');
      }
      _decodePacks(bytes, entry.file);
      await File(
        p.join(staging.path, entry.file),
      ).writeAsBytes(bytes, flush: true);
    }

    await cacheDir.create(recursive: true);
    for (final entry in manifest.files) {
      final source = File(p.join(staging.path, entry.file));
      await source.rename(p.join(cacheDir.path, entry.file));
    }
    // 清单最后落盘：中途崩溃时旧清单仍指向旧文件。
    final manifestFile = File(p.join(cacheDir.path, rulePackManifestFileName));
    await manifestFile.writeAsString(
      jsonEncode(manifest.toJson()),
      flush: true,
    );

    _cache = null;
    final packs = await loadAgentRulePacks(
      refresh: true,
      bundle: bundle,
      cacheDirectory: cacheDirectory,
    );
    return AgentRulePackUpdateResult(
      outcome: AgentRulePackUpdateOutcome.updated,
      version: manifest.version,
      message: '${packs.length}',
    );
  } catch (error, stackTrace) {
    _log.error(
      'refresh rule packs failed url=$url',
      error: error,
      stackTrace: stackTrace,
    );
    return AgentRulePackUpdateResult.failed(_describeError(error));
  } finally {
    if (staging != null && await staging.exists()) {
      try {
        await staging.delete(recursive: true);
      } catch (_) {
        // 临时目录清理失败不影响结果。
      }
    }
    owned?.close(force: true);
  }
}

/// 删除热更缓存，回到安装包内置的规则库。
Future<void> resetAgentRulePacksToBundled({
  Future<Directory> Function()? cacheDirectory,
}) async {
  final dir = await _resolveCacheDirectory(cacheDirectory);
  if (await dir.exists()) {
    await for (final entity in dir.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (error, stackTrace) {
        _log.error(
          'reset rule packs failed path=${entity.path}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }
  _cache = null;
}

Future<Directory> _resolveCacheDirectory(
  Future<Directory> Function()? override,
) async {
  if (override != null) {
    return override();
  }
  try {
    return Directory(p.join(RevericPaths.supportRoot, rulePackCacheFolderName));
  } on StateError {
    // 启动早期或纯 Dart 测试环境尚未初始化资源根目录，继续按平台目录兜底。
  }
  try {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, rulePackCacheFolderName));
  } catch (error, stackTrace) {
    _log.error(
      'resolve rule pack cache directory failed',
      error: error,
      stackTrace: stackTrace,
    );
    return Directory(
      p.join(Directory.systemTemp.path, rulePackCacheFolderName),
    );
  }
}

Dio _createClient() => Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: const {'Accept': 'application/json'},
  ),
);

Future<List<int>> _download(Dio client, String url, int maxBytes) async {
  final response = await client.get<List<int>>(
    url,
    options: Options(
      responseType: ResponseType.bytes,
      followRedirects: true,
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  final data = response.data;
  if (data == null) {
    throw FormatException('响应为空: $url');
  }
  if (data.length > maxBytes) {
    throw FormatException('响应超过体积上限: $url');
  }
  return data;
}

String _resolveFileUrl(String manifestUrl, String file) {
  final base = Uri.parse(manifestUrl);
  return base
      .replace(path: p.posix.join(p.posix.dirname(base.path), file))
      .toString();
}

String _describeError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    return status == null ? '网络不可用' : '网络错误 $status';
  }
  if (error is FormatException) {
    return '数据校验失败：${error.message}';
  }
  return '更新失败';
}

Future<int> _readManifestVersion(AssetBundle loader) async {
  try {
    final raw = await loader.loadString(rulePackAssetManifestPath);
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      final version = decoded['version'];
      if (version is int && version > 0) {
        return version;
      }
    }
  } catch (error, stackTrace) {
    _log.error(
      'read bundled manifest failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
  return 0;
}

Future<List<AgentRulePack>> _loadBundledLibrary(AssetBundle loader) async {
  final packs = <AgentRulePack>[];
  var loadedAny = false;
  for (final assetPath in rulePackAssetPaths) {
    try {
      final raw = await loader.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('$assetPath 顶层不是对象');
      }
      packs.addAll(_packsFromDecoded(decoded));
      loadedAny = true;
    } catch (error, stackTrace) {
      // 单个资源坏掉不应让整套规则库失效，其余包照常可用。
      _log.error(
        'load rule packs failed asset=$assetPath',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
  if (!loadedAny) {
    return const <AgentRulePack>[];
  }
  return _usablePacks(packs);
}

Future<_CachedLibrary?> _loadCachedLibrary(
  Directory dir,
  int bundledVersion,
) async {
  final manifestFile = File(p.join(dir.path, rulePackManifestFileName));
  if (!await manifestFile.exists()) {
    return null;
  }
  try {
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('热更清单顶层不是对象');
    }
    final manifest = AgentRulePackManifest.fromJson(decoded);
    if (cacheNotNewerThanBundled(manifest.version, bundledVersion)) {
      // 安装包自带更新版本时，内置优先。
      return null;
    }
    final packs = <AgentRulePack>[];
    for (final entry in manifest.files) {
      final file = File(p.join(dir.path, entry.file));
      if (!await file.exists()) {
        throw FormatException('缺少热更文件 ${entry.file}');
      }
      final length = await file.length();
      if (length > maxRulePackFileBytes || length != entry.bytes) {
        throw FormatException('${entry.file} 体积异常');
      }
      final bytes = await file.readAsBytes();
      if (sha256.convert(bytes).toString() != entry.sha256) {
        throw FormatException('${entry.file} 校验失败');
      }
      packs.addAll(_decodePacks(bytes, entry.file));
    }
    final usable = _usablePacks(packs);
    if (usable.isEmpty) {
      return null;
    }
    return _CachedLibrary(
      packs: usable,
      version: manifest.version,
      builtAt: manifest.builtAt,
    );
  } catch (error, stackTrace) {
    _log.error(
      'load hot-updated rule packs failed dir=${dir.path}',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}

/// 缓存版本必须严格高于内置版本，否则视为安装包已自带更新内容。
bool cacheNotNewerThanBundled(int cacheVersion, int bundledVersion) =>
    cacheVersion <= bundledVersion;

List<AgentRulePack> _decodePacks(List<int> bytes, String label) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('$label 顶层不是对象');
  }
  return _packsFromDecoded(decoded);
}

List<AgentRulePack> _packsFromDecoded(Map<String, dynamic> decoded) {
  return <AgentRulePack>[
    for (final item in (decoded['packs'] as List? ?? const []))
      if (item is Map<String, dynamic>) AgentRulePack.fromJson(item),
  ];
}

List<AgentRulePack> _usablePacks(List<AgentRulePack> packs) {
  return packs
      .where((pack) {
        return pack.id.isNotEmpty &&
            pack.name.isNotEmpty &&
            pack.rules.isNotEmpty;
      })
      .toList(growable: false);
}

class _CachedLibrary {
  const _CachedLibrary({
    required this.packs,
    required this.version,
    required this.builtAt,
  });

  final List<AgentRulePack> packs;
  final int version;
  final String builtAt;
}

/// 把规则包中的规则写入目标作品，跳过目标里已有的同名规则。
///
/// 走 [copyAgentRulesToNovel] 的同一条路径：重新生成 ID、追加排序、按名称去重。
/// 返回实际写入的条数。
Future<int> importAgentRulePack({
  required NovelContentService targetService,
  required List<AgentRule> currentRules,
  required AgentRulePack pack,
  required String targetPath,
}) async {
  final now = DateTime.now();
  final sourceRules = <AgentRule>[
    for (final rule in pack.rules)
      AgentRule(
        id: buildRandomId('pack_rule'),
        name: rule.name,
        content: rule.content,
        enabled: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
        deletedAt: notDeletedSentinel,
      ),
  ];
  return copyAgentRulesToNovel(
    targetService: targetService,
    currentRules: currentRules,
    sourceRules: sourceRules,
    sourcePath: 'rulepack:${pack.id}',
    targetPath: targetPath,
  );
}
