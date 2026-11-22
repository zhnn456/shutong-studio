// 职责: Flutter 错误日志桥接 — 保留框架默认错误展示，并同步写入 AppLogger。
// 关联文件:
//   lib/main.dart
//   lib/shared/logger/app_logger.dart
//   lib/shared/logger/startup_failure_reporter.dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_logger.dart';

final _log = AppLogger.forModule('FlutterError');

typedef FlutterErrorLogSink =
    void Function(String message, {Object? error, StackTrace? stackTrace});
typedef FlutterErrorReportSink =
    Future<void> Function(Object error, StackTrace stackTrace);

void installFlutterErrorLogger({
  FlutterExceptionHandler? presentErrorOverride,
  FlutterErrorLogSink? logErrorOverride,
  FlutterErrorReportSink? reportErrorOverride,
}) {
  FlutterError.onError = (details) {
    (presentErrorOverride ?? FlutterError.presentError)(details);
    // 只记 exceptionAsString() 时，那些"在 Element.updateChildren 里抛、栈里没有
    // 业务帧"的错误会变成一条无主线索（例如整块面板渲染成灰块，日志只留
    // Null check operator）。把 library / context / informationCollector 一起写进
    // 日志，才能定位到具体是哪个 widget 挂了。
    final buffer = StringBuffer(details.exceptionAsString());
    if (details.library != null) {
      buffer.write('\nlibrary: ${details.library}');
    }
    if (details.context != null) {
      buffer.write('\ncontext: ${details.context}');
    }
    final info = details.informationCollector?.call();
    if (info != null && info.isNotEmpty) {
      buffer.write('\n${info.join('\n')}');
    }
    (logErrorOverride ?? _log.error)(
      buffer.toString(),
      error: details.exception,
      stackTrace: details.stack,
    );
    if (reportErrorOverride != null) {
      unawaited(
        reportErrorOverride(
          details.exception,
          details.stack ?? StackTrace.current,
        ),
      );
    }
  };
}
