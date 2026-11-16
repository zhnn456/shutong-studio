// 职责: 冒烟测试 2 — 新建作品主链路（成功 / 字段校验失败 / 免费版超额拦截 三分支）。
// 关联文件:
//   lib/shared/services/novel_actions.dart（createNovel，第 77-166 行）
//   lib/shared/services/license_service.dart（LicenseService.load，免费版判定）
//   lib/shared/models/license.dart（NovelFreeLimitException / kFreeTierNovelLimit）
//
// 约束: 内存 drift 数据库；内容库工厂以 no-op seed / close 占位，不写真实业务 sqlite；
//       SharedPreferences 置空初始值 → LicenseService.load() 回退为免费版；不访问网络。

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/license.dart';
import 'package:reveric/shared/models/novel_type.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/utils/storage_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDb;

  setUp(() {
    appDb = AppDatabase.forTest(NativeDatabase.memory());
  });

  tearDown(() async {
    await NovelContentDatabase.closeAllCached();
    await appDb.close();
  });

  /// 为内容库路径解析准备临时目录（mock path_provider），并初始化存储根。
  Future<Directory> _configureTemporaryStorage(String prefix) async {
    final tempDir = await Directory.systemTemp.createTemp('smoke_${prefix}_');
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await NovelContentDatabase.closeAllCached();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? tempDir.path
              : null,
        );
    await RevericPaths.initialize();
    return tempDir;
  }

  NovelActionsService _service() => NovelActionsService(
    appDb,
    seedNovelWorkspace: (_) async {},
    seedScreenplayWorkspace: (_, _) async {},
    closeContentDatabase: (_) async {},
  );

  group('NovelActionsService.createNovel 主链路', () {
    test('分支 1：正常创建成功 — 返回 novel_ 前缀 id，书库存在对应记录', () async {
      await _configureTemporaryStorage('success');
      SharedPreferences.setMockInitialValues({});

      final service = _service();
      final novelId = await service.createNovel(
        title: '冒烟-正常作品',
        description: '主链路验证',
      );

      expect(novelId, startsWith('nov_'));
      final novel = await appDb.novelDao.get(novelId);
      expect(novel, isNotNull);
      expect(novel!.title, '冒烟-正常作品');
      expect(novel.type, novelTypeOriginal);
    });

    test('分支 2：字段/标题校验失败 — 非草稿重名抛 NovelTitleConflictException', () async {
      // 标题唯一性是书架全局校验（不区分小说/剧本，见 novel_dao.dart:75-83）。
      // 用剧本类型绕开小说额度门禁（gate 只对 contentKindNovel 生效），
      // 从而在不构造已激活授权的前提下单独验证标题冲突分支。
      await _configureTemporaryStorage('conflict');
      SharedPreferences.setMockInitialValues({});

      final service = _service();
      await service.createNovel(
        title: '重名剧本',
        description: '第一部',
        contentKind: contentKindScreenplay,
      );

      await expectLater(
        service.createNovel(
          title: '重名剧本',
          description: '第二部',
          contentKind: contentKindScreenplay,
        ),
        throwsA(
          isA<NovelTitleConflictException>().having(
            (error) => error.title,
            'title',
            '重名剧本',
          ),
        ),
      );

      // 校验失败不得在书库留下第二条同名记录。
      final all = await appDb.novelDao.getAll();
      expect(all.where((n) => n.title == '重名剧本'), hasLength(1));
    });

    test('分支 3：免费版已有 1 部小说时，再次创建被 NovelFreeLimitException 拦截', () async {
      await _configureTemporaryStorage('free_limit');
      // 空 prefs → LicenseState.free()（未激活、isUsable == false）。
      SharedPreferences.setMockInitialValues({});

      await appDb.novelDao.create(
        id: 'existing_free_novel',
        title: '既有免费作品',
        description: '',
      );

      final service = _service();
      await expectLater(
        service.createNovel(title: '第二部小说', description: ''),
        throwsA(
          isA<NovelFreeLimitException>().having(
            (error) => error.limit,
            'limit',
            kFreeTierNovelLimit,
          ),
        ),
      );

      // 拦截后书库仍然只有既有那一部。
      expect(await appDb.novelDao.getAll(), hasLength(1));
    });
  });
}
