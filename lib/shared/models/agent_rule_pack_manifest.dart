// 职责: 规则库热更清单（manifest）的数据模型与校验，供内置资源与远端下载共用。
// 关联文件:
//   lib/shared/services/agent_rule_pack_service.dart
//   rule_packs/manifest.json
//   assets/rule_packs/rule_packs.json
//   assets/rule_packs/short_drama_packs.json
//   tools/build_rule_pack_manifest.py
/// 清单中的一个规则库数据文件：文件名、字节数、内容 sha256。
class AgentRulePackManifestFile {
  const AgentRulePackManifestFile({
    required this.file,
    required this.bytes,
    required this.sha256,
  });

  factory AgentRulePackManifestFile.fromJson(Map<String, dynamic> json) {
    final file = (json['file'] as String? ?? '').trim();
    final sha256 = (json['sha256'] as String? ?? '').trim().toLowerCase();
    final bytes = json['bytes'];
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]*\.json$').hasMatch(file)) {
      throw FormatException('非法规则库文件名: $file');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw FormatException('非法 sha256: $sha256');
    }
    if (bytes is! int || bytes <= 0) {
      throw FormatException('非法字节数: $bytes');
    }
    return AgentRulePackManifestFile(file: file, bytes: bytes, sha256: sha256);
  }

  final String file;
  final int bytes;
  final String sha256;
}

/// 规则库热更清单：版本号、构建时间与数据文件列表。
class AgentRulePackManifest {
  const AgentRulePackManifest({
    required this.version,
    required this.builtAt,
    required this.files,
  });

  factory AgentRulePackManifest.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int || version <= 0) {
      throw FormatException('规则库清单 version 非法: $version');
    }
    final schema = json['schema'];
    if (schema is! int || schema != supportedSchema) {
      throw FormatException('规则库清单 schema 不受支持: $schema');
    }
    final rawFiles = json['files'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      throw const FormatException('规则库清单缺少 files');
    }
    final files = <AgentRulePackManifestFile>[
      for (final item in rawFiles)
        if (item is Map<String, dynamic>)
          AgentRulePackManifestFile.fromJson(item),
    ];
    if (files.length != rawFiles.length) {
      throw const FormatException('规则库清单 files 存在非法条目');
    }
    return AgentRulePackManifest(
      version: version,
      builtAt: (json['builtAt'] as String? ?? '').trim(),
      files: files,
    );
  }

  /// 清单结构版本；结构变化时才需要随安装包升级。
  static const int supportedSchema = 1;

  final int version;
  final String builtAt;
  final List<AgentRulePackManifestFile> files;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema': supportedSchema,
    'version': version,
    'builtAt': builtAt,
    'files': [
      for (final file in files)
        <String, dynamic>{
          'file': file.file,
          'bytes': file.bytes,
          'sha256': file.sha256,
        },
    ],
  };

  /// 当前清单是否比 [other] 新；同版本不重复下载。
  bool isNewerThan(AgentRulePackManifest? other) =>
      other == null || version > other.version;
}
