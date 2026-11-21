// 职责: 世界观手册「保存 + 记版本 + 读回」链路的真实数据库往返测试。
// 关联文件:
//   lib/shared/services/world_manual.dart
//   lib/shared/database/novel_content_database.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/world_manual.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('世界观手册保存与版本链路', () {
    late NovelContentDatabase db;

    setUp(() {
      db = NovelContentDatabase.forTest(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('首次保存写入一条记录，二次保存原地更新不新增', () async {
      final first = await saveWorldManual(
        db,
        const WorldManual(name: '汴京诡卷', oneLine: '一座会吃人的城'),
        '汴京诡卷',
      );
      final docAfterFirst = await readWorldManualDoc(db);
      expect(docAfterFirst, isNotNull);
      expect(docAfterFirst!.id, first);
      expect(docAfterFirst.type, worldManualDocType);

      final readBack = await readWorldManual(db);
      expect(readBack, isNotNull);
      expect(readBack!.oneLine, '一座会吃人的城');

      final second = await saveWorldManual(
        db,
        const WorldManual(name: '汴京诡卷', oneLine: '城会吃人，人也会吃城'),
        '汴京诡卷',
      );
      expect(second, first, reason: '同一本书只保留一条手册记录');

      final docAfterSecond = await readWorldManualDoc(db);
      expect(docAfterSecond!.id, first);
      expect(await readWorldManual(db), isNotNull);
      expect((await readWorldManual(db))!.oneLine, '城会吃人，人也会吃城');
      expect(docAfterSecond.updatedAt, isNotNull);
    });

    test('记版本生成递增快照，并挂在手册记录下', () async {
      final manualId = await saveWorldManual(
        db,
        const WorldManual(name: '汴京诡卷', oneLine: '第一版'),
        '汴京诡卷',
      );
      expect(await listWorldManualVersions(db), isEmpty);

      final v1 = await snapshotWorldManual(
        db,
        const WorldManual(name: '汴京诡卷', oneLine: '第一版'),
        '初稿',
      );
      expect(v1, 1);

      final v2 = await snapshotWorldManual(
        db,
        const WorldManual(name: '汴京诡卷', oneLine: '第二版'),
        '改冲突',
      );
      expect(v2, 2);

      final versions = await listWorldManualVersions(db);
      expect(versions.length, 2);
      expect(versions.first.version, 2, reason: '新的在前');
      expect(versions.first.note, 'v2 · 改冲突');
      expect(versions.first.snapshot.oneLine, '第二版');
      expect(versions.last.version, 1);
      expect(versions.last.snapshot.oneLine, '第一版');

      final versionDoc = await (db.select(db.documents)
            ..where((t) => t.type.equals(worldManualVersionDocType)))
          .get();
      expect(versionDoc.every((row) => row.parentId == manualId), isTrue);
    });

    test('没有手册时也能单独记版本，读回为空', () async {
      final v = await snapshotWorldManual(
        db,
        const WorldManual(oneLine: '未落盘先存档'),
        '',
      );
      expect(v, 1);
      expect(await readWorldManual(db), isNull);
      final versions = await listWorldManualVersions(db);
      expect(versions.length, 1);
      expect(versions.first.snapshot.oneLine, '未落盘先存档');
    });
  });
}
