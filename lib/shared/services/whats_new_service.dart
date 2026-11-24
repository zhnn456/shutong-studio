// 职责: 读取内置的本地更新说明（assets/updates/changelog.json），判断当前版本是否还没被用户看过。
// 关联文件:
//   lib/desktop/widgets/whats_new/whats_new_host.dart
//   assets/updates/changelog.json
//   pubspec.yaml（assets 需声明 assets/updates/，否则打包后读不到）
//   lib/shared/app_config.dart（appVersion 为当前版本号）
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';

/// 一条本地更新说明。文案按语言键存放，缺对应语言时回落中文。
class WhatsNewRelease {
  const WhatsNewRelease({
    required this.version,
    required this.date,
    required this.titles,
    required this.items,
  });

  final String version;
  final String date;
  final Map<String, String> titles;
  final List<Map<String, String>> items;

  String title(String languageCode) => _pick(titles, languageCode);

  String itemAt(int index, String languageCode) =>
      _pick(items[index], languageCode);

  static String _pick(Map<String, String> map, String languageCode) {
    final exact = map[languageCode];
    if (exact != null && exact.isNotEmpty) return exact;
    final zh = map['zh'];
    if (zh != null && zh.isNotEmpty) return zh;
    return map.isEmpty ? '' : map.values.first;
  }

  static Map<String, String> _localizedMap(dynamic raw) {
    if (raw is! Map) return const <String, String>{};
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (value == null) return;
      result[key.toString()] = value.toString();
    });
    return result;
  }

  /// 解析单条 release；字段缺失时用空值兜底，不让一条坏数据挡住整次展示。
  factory WhatsNewRelease.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <Map<String, String>>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        final map = _localizedMap(entry);
        if (map.isNotEmpty) items.add(map);
      }
    }
    return WhatsNewRelease(
      version: json['version']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      titles: _localizedMap(json['title']),
      items: items,
    );
  }
}

/// 本地更新说明的读取与「已读」记录。
/// 口径：只有版本号变了才展示，同一版本展示过一次就不再出现。
class WhatsNewService {
  const WhatsNewService();

  static const _seenVersionKey = 'whats_new_seen_version';
  static const _assetPath = 'assets/updates/changelog.json';

  /// 当前版本存在说明、且用户还没看过时返回该条；任何异常一律静默返回 null。
  Future<WhatsNewRelease?> pendingRelease() async {
    try {
      final release = await _releaseForVersion(appVersion);
      if (release == null || release.items.isEmpty) return null;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_seenVersionKey) == appVersion) return null;
      return release;
    } catch (_) {
      return null;
    }
  }

  /// 用户关掉浮窗后落盘；写失败也不影响主流程，下次最多再弹一次。
  Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_seenVersionKey, appVersion);
    } catch (_) {
      // 忽略：写不进去只会导致重复展示，不阻塞使用。
    }
  }

  Future<WhatsNewRelease?> _releaseForVersion(String version) async {
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final list = decoded['releases'];
    if (list is! List) return null;
    for (final entry in list) {
      if (entry is! Map) continue;
      if (entry['version']?.toString() != version) continue;
      return WhatsNewRelease.fromJson(Map<String, dynamic>.from(entry));
    }
    return null;
  }
}
