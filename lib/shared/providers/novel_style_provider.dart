// 职责: 文风样文的读取入口 — plain Riverpod，避免新增 codegen。
// 关联文件:
//   lib/shared/services/novel_style.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/novel_style.dart';
import 'novel_providers.dart';

final novelStyleProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, novelId) async {
    final database = ref.watch(appDatabaseProvider);
    return readNovelStyle(database, novelId);
  },
);
