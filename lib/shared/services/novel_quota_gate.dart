// 职责: 免费版作品数量门禁的唯一判定入口。
//   所有"新建/种入/恢复"作品的路径都必须经过这里，避免出现绕过门禁的旁路。
// 关联文件:
//   lib/shared/models/license.dart      （LicenseState / kFreeTierNovelLimit / NovelFreeLimitException）
//   lib/shared/models/content_kind.dart （contentKindNovel）
//   lib/shared/services/license_service.dart
//   lib/shared/services/novel_actions.dart
//   lib/shared/services/demo_novel.dart
//   lib/shared/services/app_initialization.dart
//   lib/shared/services/backup_service.dart
//
// 规则:
//   - 已授权（isUsable）一律放行。
//   - 未授权：现有小说数 + 本次新增数 <= 额度（默认 1，可被服务端 features.max_novels 覆盖）。
//   - 剧本不计入小说额度。
//   - 超出即抛 NovelFreeLimitException，由调用方决定提示方式。
import '../database/app_database.dart';
import '../models/content_kind.dart';
import '../models/license.dart';
import 'license_service.dart';

/// 免费版额度判定。
class NovelQuotaGate {
  const NovelQuotaGate._();

  /// 当前生效的小说数量上限（未授权时）。
  static Future<int> freeLimit() async {
    final license = await LicenseService.load();
    return license.novelLimit ?? kFreeTierNovelLimit;
  }

  /// 未授权时校验"还能不能再加 [incoming] 部小说"。
  /// 超出抛 [NovelFreeLimitException]；已授权直接放行。
  static Future<void> ensureCanAdd(
    AppDatabase database, {
    int incoming = 1,
  }) async {
    final license = await LicenseService.load();
    if (license.isUsable) {
      return;
    }
    final limit = license.novelLimit ?? kFreeTierNovelLimit;
    final existing = (await database.novelDao.getAll())
        .where((novel) => novel.contentKind == contentKindNovel)
        .length;
    if (existing + incoming > limit) {
      throw NovelFreeLimitException(limit);
    }
  }

  /// 纯计数版本，供不方便拿 AppDatabase 的调用方（如恢复流程）使用。
  /// 只判断"本次新增数量是否已经超额度"，不叠加现有数量。
  static Future<void> ensureIncomingWithinLimit(int incoming) async {
    final license = await LicenseService.load();
    if (license.isUsable) {
      return;
    }
    final limit = license.novelLimit ?? kFreeTierNovelLimit;
    if (incoming > limit) {
      throw NovelFreeLimitException(limit);
    }
  }
}
