// 职责: 「世界观手册 / 世界观样本库」的读写、样本导入与确定性一致性检查。
//
// 设计口径（重要，后续改动请遵守）：
//   * 手册不新建第二套设定库。五段世界印象 + 四个区块是「书级的一条记录」，
//     存在 documents 表里（type=world_manual，content=JSON）；势力 / 地点 / 人物
//     仍然读现有实体表，只做聚合展示，不复制一份。
//   * 版本快照也走 documents 表（type=world_manual_version，parentId=手册 id）。
//   * 用户自建样本走 documents 表（type=world_sample）；内置样本随包走 assets JSON。
//   * 一致性检查只做「能确定性判定」的问题，不调模型、不做猜测。
//
// 关联文件:
//   lib/desktop/widgets/workspace/world_manual_panel.dart
//   lib/shared/providers/world_manual_provider.dart
//   assets/world_samples.json
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../database/novel_content_database.dart';

/// 书级手册记录。
const String worldManualDocType = 'world_manual';

/// 手册版本快照。
const String worldManualVersionDocType = 'world_manual_version';

/// 用户自建 / 从内置复制的样本。
const String worldSampleDocType = 'world_sample';

/// 手册默认标题。
const String worldManualDefaultTitle = '世界观手册';

/// 内置样本包路径。
const String worldSamplesAssetPath = 'assets/world_samples.json';

/// 单个文本字段的长度上限，防止一次粘贴整本设定把 AI 上下文打爆。
const int worldManualFieldMaxCharacters = 4000;

/// 手册的一条数据。字段与界面一一对应，不做嵌套，便于版本对比。
class WorldManual {
  const WorldManual({
    this.name = '',
    this.impressionTags = '',
    this.oneLine = '',
    this.readerGlimpse = '',
    this.tone = '',
    this.coreConflict = '',
    this.rulesSummary = '',
    this.rulesDetail = '',
    this.factionsActive = '',
    this.factionsPressure = '',
    this.locationsAvailable = '',
    this.locationsRisk = '',
    this.tensionRelations = '',
    this.tensionOutcome = '',
    this.sampleId = '',
  });

  /// 手册名（通常等于样本名，作者可改）。
  final String name;

  /// 世界印象标签，英文逗号分隔。
  final String impressionTags;

  /// 一句话世界印象。
  final String oneLine;

  /// 读者一眼。
  final String readerGlimpse;

  /// 阅读气质。
  final String tone;

  /// 持续推动剧情的矛盾。
  final String coreConflict;

  /// 核心规则 · 规则总纲。
  final String rulesSummary;

  /// 核心规则 · 代表性规则。
  final String rulesDetail;

  /// 主要势力 · 活跃势力。
  final String factionsActive;

  /// 主要势力 · 故事压力。
  final String factionsPressure;

  /// 故事舞台 · 可用地点。
  final String locationsAvailable;

  /// 故事舞台 · 进入风险。
  final String locationsRisk;

  /// 冲突张力 · 势力关系。
  final String tensionRelations;

  /// 冲突张力 · 共同后果。
  final String tensionOutcome;

  /// 套用的样本 id（内置样本为 builtin:xxx）。
  final String sampleId;

  /// 五段印象是否都填了。
  bool get impressionComplete =>
      oneLine.trim().isNotEmpty &&
      readerGlimpse.trim().isNotEmpty &&
      tone.trim().isNotEmpty &&
      coreConflict.trim().isNotEmpty;

  /// 四个区块是否都填了。
  bool get blocksComplete =>
      rulesSummary.trim().isNotEmpty &&
      factionsActive.trim().isNotEmpty &&
      locationsAvailable.trim().isNotEmpty &&
      tensionRelations.trim().isNotEmpty;

  /// 整条记录是否为空（用于判断「这本书还没有手册」）。
  bool get isBlank =>
      oneLine.trim().isEmpty &&
      readerGlimpse.trim().isEmpty &&
      tone.trim().isEmpty &&
      coreConflict.trim().isEmpty &&
      rulesSummary.trim().isEmpty &&
      rulesDetail.trim().isEmpty &&
      factionsActive.trim().isEmpty &&
      factionsPressure.trim().isEmpty &&
      locationsAvailable.trim().isEmpty &&
      locationsRisk.trim().isEmpty &&
      tensionRelations.trim().isEmpty &&
      tensionOutcome.trim().isEmpty;

  WorldManual copyWith({
    String? name,
    String? impressionTags,
    String? oneLine,
    String? readerGlimpse,
    String? tone,
    String? coreConflict,
    String? rulesSummary,
    String? rulesDetail,
    String? factionsActive,
    String? factionsPressure,
    String? locationsAvailable,
    String? locationsRisk,
    String? tensionRelations,
    String? tensionOutcome,
    String? sampleId,
  }) {
    return WorldManual(
      name: name ?? this.name,
      impressionTags: impressionTags ?? this.impressionTags,
      oneLine: oneLine ?? this.oneLine,
      readerGlimpse: readerGlimpse ?? this.readerGlimpse,
      tone: tone ?? this.tone,
      coreConflict: coreConflict ?? this.coreConflict,
      rulesSummary: rulesSummary ?? this.rulesSummary,
      rulesDetail: rulesDetail ?? this.rulesDetail,
      factionsActive: factionsActive ?? this.factionsActive,
      factionsPressure: factionsPressure ?? this.factionsPressure,
      locationsAvailable: locationsAvailable ?? this.locationsAvailable,
      locationsRisk: locationsRisk ?? this.locationsRisk,
      tensionRelations: tensionRelations ?? this.tensionRelations,
      tensionOutcome: tensionOutcome ?? this.tensionOutcome,
      sampleId: sampleId ?? this.sampleId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'impressionTags': impressionTags,
    'oneLine': oneLine,
    'readerGlimpse': readerGlimpse,
    'tone': tone,
    'coreConflict': coreConflict,
    'rulesSummary': rulesSummary,
    'rulesDetail': rulesDetail,
    'factionsActive': factionsActive,
    'factionsPressure': factionsPressure,
    'locationsAvailable': locationsAvailable,
    'locationsRisk': locationsRisk,
    'tensionRelations': tensionRelations,
    'tensionOutcome': tensionOutcome,
    'sampleId': sampleId,
  };

  String encode() => jsonEncode(toJson());

  static WorldManual fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] as String? ?? '').trim();
    return WorldManual(
      name: read('name'),
      impressionTags: read('impressionTags'),
      oneLine: read('oneLine'),
      readerGlimpse: read('readerGlimpse'),
      tone: read('tone'),
      coreConflict: read('coreConflict'),
      rulesSummary: read('rulesSummary'),
      rulesDetail: read('rulesDetail'),
      factionsActive: read('factionsActive'),
      factionsPressure: read('factionsPressure'),
      locationsAvailable: read('locationsAvailable'),
      locationsRisk: read('locationsRisk'),
      tensionRelations: read('tensionRelations'),
      tensionOutcome: read('tensionOutcome'),
      sampleId: read('sampleId'),
    );
  }

  static WorldManual decode(String raw) {
    if (raw.trim().isEmpty) return const WorldManual();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return WorldManual.fromJson(decoded);
      }
      return const WorldManual();
    } catch (_) {
      return const WorldManual();
    }
  }

  /// 组装成可读 / 可注入 AI 的整段文本。空字段整段跳过，不留「（空）」。
  String composeText() {
    final buffer = StringBuffer();
    void section(String title, String body) {
      if (body.trim().isEmpty) return;
      buffer
        ..writeln('## $title')
        ..writeln(body.trim())
        ..writeln();
    }

    buffer.writeln('# ${name.trim().isEmpty ? worldManualDefaultTitle : name.trim()}');
    buffer.writeln();
    section('一句话世界印象', oneLine);
    section('读者一眼', readerGlimpse);
    section('阅读气质', tone);
    section('持续推动剧情的矛盾', coreConflict);
    section('核心规则 · 总纲', rulesSummary);
    section('核心规则 · 代表性规则', rulesDetail);
    section('主要势力 · 活跃势力', factionsActive);
    section('主要势力 · 故事压力', factionsPressure);
    section('故事舞台 · 可用地点', locationsAvailable);
    section('故事舞台 · 进入风险', locationsRisk);
    section('冲突张力 · 势力关系', tensionRelations);
    section('冲突张力 · 共同后果', tensionOutcome);
    return buffer.toString().trim();
  }

  /// 与另一版本逐字段比较，返回「哪些字段变了」的人话列表。
  List<String> diffFields(WorldManual other) {
    final changed = <String>[];
    void check(String label, String a, String b) {
      if (a.trim() != b.trim()) changed.add(label);
    }

    check('一句话世界印象', oneLine, other.oneLine);
    check('读者一眼', readerGlimpse, other.readerGlimpse);
    check('阅读气质', tone, other.tone);
    check('核心矛盾', coreConflict, other.coreConflict);
    check('规则总纲', rulesSummary, other.rulesSummary);
    check('代表性规则', rulesDetail, other.rulesDetail);
    check('活跃势力', factionsActive, other.factionsActive);
    check('故事压力', factionsPressure, other.factionsPressure);
    check('可用地点', locationsAvailable, other.locationsAvailable);
    check('进入风险', locationsRisk, other.locationsRisk);
    check('势力关系', tensionRelations, other.tensionRelations);
    check('共同后果', tensionOutcome, other.tensionOutcome);
    return changed;
  }
}

/// 一个版本快照条目。
class WorldManualVersionEntry {
  const WorldManualVersionEntry({
    required this.id,
    required this.version,
    required this.note,
    required this.createdAt,
    required this.snapshot,
  });

  final String id;
  final int version;
  final String note;
  final DateTime createdAt;
  final WorldManual snapshot;
}

/// 样本库里的一条样本（内置或用户自建）。
class WorldSample {
  const WorldSample({
    required this.id,
    required this.name,
    required this.genre,
    required this.summary,
    required this.manual,
    this.isBuiltin = false,
    this.factionSeeds = const <String>[],
    this.locationSeeds = const <String>[],
  });

  final String id;
  final String name;
  final String genre;
  final String summary;
  final WorldManual manual;
  final bool isBuiltin;

  /// 套用样本时一并创建的势力条目（为空则只写手册）。
  final List<String> factionSeeds;

  /// 套用样本时一并创建的地点条目。
  final List<String> locationSeeds;

  WorldSample copyWith({String? id, String? name}) {
    return WorldSample(
      id: id ?? this.id,
      name: name ?? this.name,
      genre: genre,
      summary: summary,
      manual: manual,
      isBuiltin: isBuiltin,
      factionSeeds: factionSeeds,
      locationSeeds: locationSeeds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'genre': genre,
    'summary': summary,
    'manual': manual.toJson(),
    'isBuiltin': isBuiltin,
    'factionSeeds': factionSeeds,
    'locationSeeds': locationSeeds,
  };

  static WorldSample fromJson(Map<String, dynamic> json) {
    final manualJson = json['manual'];
    return WorldSample(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      genre: json['genre'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      manual: manualJson is Map<String, dynamic>
          ? WorldManual.fromJson(manualJson)
          : const WorldManual(),
      isBuiltin: json['isBuiltin'] as bool? ?? false,
      factionSeeds: (json['factionSeeds'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      locationSeeds: (json['locationSeeds'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

/// 一致性检查结果的严重度。
enum WorldManualIssueLevel { block, warn, hint }

/// 一条确定性检查结果。[action] 说明「点这个按钮能怎么修」。
class WorldManualIssue {
  const WorldManualIssue({
    required this.title,
    required this.detail,
    required this.level,
    this.action,
  });

  final String title;
  final String detail;
  final WorldManualIssueLevel level;
  final String? action;
}

/// 读取这本书的手册文档（不解析）。
Future<Document?> readWorldManualDoc(NovelContentDatabase db) async {
  final rows =
      await (db.select(db.documents)
            ..where(
              (table) =>
                  table.type.equals(worldManualDocType) &
                  table.deletedAt.equals(notDeletedSentinel),
            )
            ..limit(1))
          .get();
  return rows.isEmpty ? null : rows.first;
}

/// 读取手套册数据。没有记录时返回 null（而不是空对象），便于区分「未建」。
Future<WorldManual?> readWorldManual(NovelContentDatabase db) async {
  final doc = await readWorldManualDoc(db);
  if (doc == null) return null;
  return WorldManual.decode(doc.content);
}

/// 写手册。新建时插入，已有记录时原地更新，并刷新 updatedAt。
Future<String> saveWorldManual(
  NovelContentDatabase db,
  WorldManual manual,
  String novelTitle,
) async {
  final existing = await readWorldManualDoc(db);
  final now = DateTime.now();
  final title = manual.name.trim().isEmpty ? worldManualDefaultTitle : manual.name.trim();
  if (existing == null) {
    final id = 'wm_${now.microsecondsSinceEpoch}';
    await db.into(db.documents).insert(
      DocumentsCompanion.insert(
        id: id,
        type: worldManualDocType,
        title: title,
        content: Value(manual.encode()),
        status: const Value('active'),
        category: Value(novelTitle),
        sortOrder: const Value(0),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return id;
  }
  await (db.update(db.documents)..where((table) => table.id.equals(existing.id)))
      .write(
        DocumentsCompanion(
          title: Value(title),
          content: Value(manual.encode()),
          category: Value(novelTitle),
          updatedAt: Value(now),
        ),
      );
  return existing.id;
}

/// 保存一个版本快照，返回新版本号。
Future<int> snapshotWorldManual(
  NovelContentDatabase db,
  WorldManual manual,
  String note,
) async {
  final manualDoc = await readWorldManualDoc(db);
  final versions = await listWorldManualVersions(db);
  final next = versions.isEmpty ? 1 : versions.first.version + 1;
  final now = DateTime.now();
  await db.into(db.documents).insert(
    DocumentsCompanion.insert(
      id: 'wmv_${now.microsecondsSinceEpoch}',
      type: worldManualVersionDocType,
      title: 'v$next${note.trim().isEmpty ? '' : ' · ${note.trim()}'}',
      content: Value(manual.encode()),
      status: const Value('active'),
      parentId: Value(manualDoc?.id),
      sortOrder: Value(next),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );
  return next;
}

/// 列出手册的版本快照，新的在前。
Future<List<WorldManualVersionEntry>> listWorldManualVersions(
  NovelContentDatabase db,
) async {
  final rows =
      await (db.select(db.documents)
            ..where(
              (table) =>
                  table.type.equals(worldManualVersionDocType) &
                  table.deletedAt.equals(notDeletedSentinel),
            )
            ..orderBy([(table) => OrderingTerm.desc(table.sortOrder)])
            ..limit(50))
          .get();
  return rows
      .map(
        (row) => WorldManualVersionEntry(
          id: row.id,
          version: row.sortOrder,
          note: row.title,
          createdAt: row.createdAt,
          snapshot: WorldManual.decode(row.content),
        ),
      )
      .toList();
}

/// 读取内置样本库（随包 assets，不做缓存以外的副作用）。
Future<List<WorldSample>> loadBuiltinWorldSamples() async {
  try {
    final raw = await rootBundle.loadString(worldSamplesAssetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <WorldSample>[];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(WorldSample.fromJson)
        .where((sample) => sample.name.trim().isNotEmpty)
        .toList();
  } catch (_) {
    return const <WorldSample>[];
  }
}

/// 读取用户自建样本。
Future<List<WorldSample>> listUserWorldSamples(NovelContentDatabase db) async {
  final rows =
      await (db.select(db.documents)
            ..where(
              (table) =>
                  table.type.equals(worldSampleDocType) &
                  table.deletedAt.equals(notDeletedSentinel),
            )
            ..orderBy([(table) => OrderingTerm.desc(table.updatedAt)]))
          .get();
  return rows
      .map((row) => WorldSample.fromJson(decodeSamplePayload(row.content)))
      .toList();
}

/// 把当前手册存成用户样本（「我用这套设定再开一本」）。
Future<String> saveWorldSampleFromManual(
  NovelContentDatabase db,
  WorldManual manual,
  String genre,
  String summary,
) async {
  final now = DateTime.now();
  final id = 'ws_${now.microsecondsSinceEpoch}';
  final sample = WorldSample(
    id: id,
    name: manual.name.trim().isEmpty ? worldManualDefaultTitle : manual.name.trim(),
    genre: genre,
    summary: summary,
    manual: manual.copyWith(sampleId: 'local:$id'),
  );
  await db.into(db.documents).insert(
    DocumentsCompanion.insert(
      id: id,
      type: worldSampleDocType,
      title: sample.name,
      content: Value(jsonEncode(sample.toJson())),
      status: const Value('active'),
      category: Value(genre),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );
  return id;
}

/// 删除用户样本。
Future<void> deleteUserWorldSample(NovelContentDatabase db, String id) async {
  await (db.delete(db.documents)..where((table) => table.id.equals(id))).go();
}

/// 套用样本：写手册 + 按种子建势力 / 地点条目（已同名的不重复建）。
///
/// 返回实际创建的条目数，供界面显示「已写入 N 个设定」。
Future<int> applyWorldSample(
  NovelContentDatabase db,
  WorldSample sample,
  String novelTitle,
) async {
  final manual = sample.manual.copyWith(sampleId: sample.id);
  await saveWorldManual(db, manual, novelTitle);

  var created = 0;
  for (final name in sample.factionSeeds) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) continue;
    final exists = await _itemExists(db, 'faction', trimmed);
    if (exists) continue;
    await _createItemEntity(db, type: 'faction', title: trimmed, content: '');
    created++;
  }
  for (final name in sample.locationSeeds) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) continue;
    final exists = await _locationExists(db, trimmed);
    if (exists) continue;
    await _createLocationEntity(db, name: trimmed, description: '');
    created++;
  }
  return created;
}

Future<bool> _itemExists(NovelContentDatabase db, String type, String title) async {
  final rows =
      await (db.select(db.items)
            ..where(
              (table) =>
                  table.type.equals(type) &
                  table.title.equals(title) &
                  table.deletedAt.equals(notDeletedSentinel),
            )
            ..limit(1))
          .get();
  return rows.isNotEmpty;
}

Future<bool> _locationExists(NovelContentDatabase db, String name) async {
  final rows =
      await (db.select(db.locations)
            ..where(
              (table) =>
                  table.name.equals(name) &
                  table.deletedAt.equals(notDeletedSentinel),
            )
            ..limit(1))
          .get();
  return rows.isNotEmpty;
}

var _worldIdSeed = 0;

String _nextWorldId(String prefix) {
  _worldIdSeed++;
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_worldIdSeed';
}

Future<void> _createItemEntity(
  NovelContentDatabase db, {
  required String type,
  required String title,
  required String content,
}) async {
  final now = DateTime.now();
  await db.into(db.items).insert(
    ItemsCompanion.insert(
      id: _nextWorldId('it'),
      type: type,
      title: title,
      content: Value(content),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );
}

Future<void> _createLocationEntity(
  NovelContentDatabase db, {
  required String name,
  required String description,
}) async {
  final now = DateTime.now();
  await db.into(db.locations).insert(
    LocationsCompanion.insert(
      id: _nextWorldId('loc'),
      name: name,
      description: Value(description),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );
}

/// 名称对不上检查用：把自由文本里出现的「、」「/」「，」拆成名字。
List<String> splitNames(String raw) {
  return raw
      .split(RegExp(r'[、/，,；;\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

/// 手册里的势力和地点如果填了名字，但实体列表里找不到同名，就是「写了但没建」。
List<WorldManualIssue> checkNameDrift({
  required WorldManual manual,
  required List<String> factionNames,
  required List<String> locationNames,
}) {
  final issues = <WorldManualIssue>[];
  void checkBlock(String label, String raw, List<String> existing) {
    if (raw.trim().isEmpty) return;
    final missing = splitNames(raw)
        .where((name) => name.length >= 2 && !existing.contains(name))
        .toList();
    if (missing.isEmpty) return;
    issues.add(
      WorldManualIssue(
        title: '${label}里有名字没有对应条目',
        detail: '手册写了「${missing.take(4).join('、')}」，但${label}列表里找不到同名条目。'
            '读者看到的是名字，写手拿到的是空条目，最容易在这里出基础错误。',
        level: WorldManualIssueLevel.warn,
        action: '按手册补建条目',
      ),
    );
  }

  checkBlock('势力', manual.factionsActive, factionNames);
  checkBlock('地点', manual.locationsAvailable, locationNames);
  return issues;
}

/// 用户样本（documents.type=world_sample）的 content 是完整样本 JSON，
/// 不是手册 JSON，单独解一个入口，避免把两种结构混淆。
Map<String, dynamic> decodeSamplePayload(String raw) {
  if (raw.trim().isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}
