// 职责: 冒烟测试 4 — 托盘退出可靠性回归（对应修复提交 dcdd38b）。
// 关联文件:
//   lib/shared/services/system_tray_service.dart（_exitApplication / exitApplicationForTesting）
//
// 覆盖分支:
//   a. guard 返回 false（取消退出）→ 不调用进程终止；
//   b. guard 抛异常 → 不阻断，最终仍调用 terminate；
//   c. guard 永不返回（卡死）→ 6s 超时兜底生效，最终仍调用 terminate；
//   d. 实例锁释放抛异常 / 超时 → 记录上报但不阻断 terminate；
//   e. tray destroy 与 window close 的 MethodChannel 回包不挂起时，退出不被阻塞。
//
// 说明: _exitGuards 是单例内部列表；每个用例注册后显式 unregister，避免跨用例残留。

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/logger/startup_failure_reporter.dart';
import 'package:reveric/shared/services/system_tray_service.dart';
import 'package:tray_manager/tray_manager.dart' as tray;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowManagerChannel = MethodChannel('window_manager');
  final calls = <String>[];
  Completer<Object?>? pendingWindowClose;

  setUp(() {
    calls.clear();
    pendingWindowClose = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (call) async {
          calls.add('window.${call.method}');
          if (call.method == 'close' && pendingWindowClose != null) {
            return pendingWindowClose!.future;
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, null);
  });

  Future<void> _exit({
    Future<bool> Function()? guard,
    FutureOr<void> Function()? unlock,
    StartupFailureReporter? reporter,
  }) async {
    String? terminateCode;
    void recordTerminate(int code) => terminateCode = '$code';
    final unregister = guard == null
        ? null
        : SystemTrayService().registerExitGuard(guard);
    await SystemTrayService()
        .exitApplicationForTesting(
          recordTerminate,
          unlock: unlock,
          failureReporter: reporter,
        )
        .timeout(const Duration(seconds: 10));
    unregister?.call();
    if (terminateCode != null) {
      calls.add('exit.$terminateCode');
    }
  }

  group('退出 guard 语义', () {
    test('a. guard 返回 false 取消退出：不调用 terminate', () async {
      await _exit(guard: () async => false);
      expect(calls, isEmpty);
    });

    test('b. guard 抛异常：记录后继续走退出流程，仍调用 terminate', () async {
      await _exit(
        guard: () => throw StateError('guard exploded'),
      );
      expect(calls, contains('exit.0'));
    });

    test('c. guard 永不返回：超时兜底生效，退出流程不卡死并调用 terminate', () async {
      final hung = Completer<bool>(); // 永不 complete
      final stopwatch = Stopwatch()..start();
      await _exit(guard: () => hung.future);
      stopwatch.stop();

      expect(calls, contains('exit.0'));
      // 兜底预算为 _guardBudget = 6s；断言确实等待过超时（>1s）且整体在 10s 内返回。
      expect(stopwatch.elapsedMilliseconds, greaterThan(1000));
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
    });
  });

  group('退出清理步骤失败的兜底', () {
    test('d. 实例锁释放抛异常：走失败上报，仍调用 terminate', () async {
      final reporter = _RecordingReporter(calls);
      await _exit(
        unlock: () => throw StateError('instance unlock failed'),
        reporter: reporter,
      );
      expect(
        calls,
        containsAllInOrder([
          'report:tray_exit:release_instance_failed',
          'exit.0',
        ]),
      );
    });

    test('e1. 托盘清理抛异常：错误被吞掉，仍请求关窗并 terminate', () async {
      final service = SystemTrayService.forTesting(_BoomTrayIcon());
      String? terminateCode;
      await service
          .exitApplicationForTesting((code) => terminateCode = '$code')
          .timeout(const Duration(seconds: 10));

      expect(terminateCode, '0');
      expect(
        calls,
        containsAllInOrder(['window.setPreventClose', 'window.close']),
      );
    });

    test('e2. window close 回包不返回：close 不被 await，terminate 照常调用', () async {
      pendingWindowClose = Completer<Object?>();
      await _exit();
      expect(calls, <String>[
        'window.setPreventClose',
        'window.close',
        'exit.0',
      ]);
    });

    test('正常退出调用序列：解除防关闭 → 请求关窗 → 终止进程', () async {
      await _exit();
      expect(calls, <String>[
        'window.setPreventClose',
        'window.close',
        'exit.0',
      ]);
    });
  });
}

class _BoomTrayIcon implements tray.TrayIcon {
  @override
  void dispose() => throw StateError('native disposal failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingReporter extends StartupFailureReporter {
  _RecordingReporter(this.calls);

  final List<String> calls;

  @override
  Future<void> reportLifecycleFailure({
    required String phase,
    required String reason,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    calls.add('report:$phase:$reason');
  }
}
