// 职责: 系统托盘服务 — 管理托盘图标、菜单与关闭到托盘行为
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/widgets/confirm_dialog.dart
//   lib/main.dart
//   lib/shared/services/window_state_service.dart
//   lib/desktop/widgets/novel_form_dialog.dart
//   lib/desktop/pages/workspace_editor_page.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/models/novel_type.dart
//   lib/shared/database/app_database.dart
//   lib/shared/database/novel_content_database.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart' as tray;

import '../components/dialog_feedback.dart';
import '../database/app_database.dart';
import '../database/novel_content_database.dart';
import '../logger/app_logger.dart';
import '../logger/startup_failure_reporter.dart';
import 'crash_reporting/crash_sentinel.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'single_instance_service.dart';
import '../../desktop/widgets/novel_form_dialog.dart';
import '../providers/novel_providers.dart';
import '../../desktop/pages/workspace_editor_page.dart';
import '../components/reveric_dialog.dart';
import '../widgets/confirm_dialog.dart';

final _log = AppLogger.forModule('SystemTray');

class SystemTrayService {
  final List<Future<bool> Function()> _exitGuards = [];
  VoidCallback registerExitGuard(Future<bool> Function() guard) {
    _exitGuards.add(guard);
    return () => _exitGuards.remove(guard);
  }

  static String get _iconPath {
    if (Platform.isWindows) {
      return 'assets/logo/reveric_mark_32.ico';
    }
    return 'assets/logo/reveric_mark_32.png';
  }

  static final SystemTrayService _instance = SystemTrayService._internal();
  factory SystemTrayService() => _instance;
  SystemTrayService._internal();

  @visibleForTesting
  SystemTrayService.forTesting(this._trayIcon);

  tray.TrayIcon? _trayIcon;
  tray.Image? _icon;
  tray.Menu? _menu;
  tray.ListenerId? _trayListener;
  final _menuItems = <(tray.MenuItem, tray.ListenerId)>[];

  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  bool _initialized = false;

  /// 单个退出 guard 的等待上限。guard 自身卡住（例如深度任务停止时挂死）
  /// 绝不能把整个退出流程一起拖住，否则用户看到的还是"点了退出没反应"。
  static const Duration _guardBudget = Duration(seconds: 6);

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    try {
      final icon = tray.ImageAsset.fromAsset(_iconPath);
      if (icon == null) {
        throw StateError('Unable to load tray icon: $_iconPath');
      }
      _icon = icon;
      final trayIcon = tray.TrayIcon.create();
      if (trayIcon == null) {
        throw StateError('Unable to create tray icon');
      }
      _trayIcon = trayIcon;
      trayIcon
        ..isIconTemplate = true
        ..icon = icon
        ..setTooltip('Reveric');
      _trayListener = trayIcon.addListener((event) async {
        if (event is tray.TrayIconClickedEvent) {
          await showMainWindow();
        }
      });
      _updateMenu(trayIcon);
      if (!trayIcon.setVisible(true)) {
        throw StateError('Unable to show tray icon');
      }

      await windowManager.setPreventClose(true);
      windowManager.addListener(_WindowCloseListener());

      _initialized = true;
      _log.info('System tray initialized');
    } catch (error, stackTrace) {
      _disposeTray();
      _log.warning('Failed to initialize system tray: $error\n$stackTrace');
    }
  }

  void _updateMenu(tray.TrayIcon trayIcon) {
    final menu = tray.Menu.create();
    if (menu == null) {
      throw StateError('Unable to create tray menu');
    }
    _menu = menu;

    void addItem(String label, Future<void> Function() action) {
      final item = tray.MenuItem.createWithLabelAndType(
        label,
        tray.MenuItemType.normal,
      );
      if (item == null) {
        throw StateError('Unable to create tray menu item: $label');
      }
      final listener = item.addListener((event) async {
        if (event is tray.MenuItemClickedEvent) {
          await action();
        }
      });
      _menuItems.add((item, listener));
      menu.addItem(item);
    }

    addItem('新建小说', _newNovel);
    menu.addSeparator();
    addItem('隐藏', _hideWindow);
    addItem('显示', showMainWindow);
    menu.addSeparator();
    addItem('退出', _quit);
    trayIcon
      ..setContextMenu(menu)
      ..setContextMenuTrigger(tray.ContextMenuTrigger.rightClicked);
  }

  void _disposeTray() {
    final trayIcon = _trayIcon;
    final listener = _trayListener;
    if (trayIcon != null && listener != null) {
      try {
        trayIcon.removeListener(listener);
      } catch (error, stackTrace) {
        _log.warning('tray removeListener failed error=$error\n$stackTrace');
      }
    }
    _trayListener = null;
    for (final (item, listener) in _menuItems) {
      try {
        item.removeListener(listener);
        item.dispose();
      } catch (error, stackTrace) {
        _log.warning('tray item dispose failed error=$error\n$stackTrace');
      }
    }
    _menuItems.clear();
    try {
      trayIcon?.dispose();
    } catch (error, stackTrace) {
      _log.warning('tray dispose failed error=$error\n$stackTrace');
    }
    _trayIcon = null;
    try {
      _menu?.dispose();
    } catch (error, stackTrace) {
      _log.warning('tray menu dispose failed error=$error\n$stackTrace');
    }
    _menu = null;
    _icon?.dispose();
    _icon = null;
  }

  /// 唤起主窗口：托盘点击、托盘菜单与第二实例激活请求共用。
  Future<void> showMainWindow() async {
    _log.checkpoint('showing main window (native)');
    await windowManager.show();
    await windowManager.focus();
    final visible = await windowManager.isVisible();
    final minimized = await windowManager.isMinimized();
    _log.checkpoint(
      'main window activation result visible=$visible minimized=$minimized',
    );
    if (!visible || minimized) {
      throw StateError('Window did not become visible after activation');
    }
    _log.checkpoint('main window activation verified (native)');
  }

  Future<void> _hideWindow() async {
    _log.checkpoint('hiding main window (native)');
    await windowManager.hide();
  }

  Future<void> _newNovel() async {
    await showMainWindow();
    final context = navigatorKey.currentState?.context;
    if (context == null || !context.mounted) {
      return;
    }
    showRevericDialog(
      context: context,
      builder: (ctx) => DialogFeedback.scope(
        builder: (ctx) => NovelFormDialog.create(
          onSubmit:
              ({
                required String title,
                required String authorName,
                required String description,
                required String category,
                required String type,
                required String contentKind,
                required int? plannedEpisodeCount,
                required String? sourceNovelId,
                required String? coverSourcePath,
                required bool removeCover,
                required List<String> tags,
              }) async {
                final container = ProviderScope.containerOf(ctx);
                final actions = container.read(novelActionsProvider);
                try {
                  final novelId = await actions.createNovel(
                    title: title,
                    authorName: authorName,
                    description: description,
                    category: category,
                    type: type,
                    contentKind: contentKind,
                    plannedEpisodeCount: plannedEpisodeCount,
                    sourceNovelId: sourceNovelId,
                    coverSourcePath: coverSourcePath,
                    tags: tags,
                  );
                  if (!ctx.mounted) return false;
                  final navigator = Navigator.of(ctx);
                  Navigator.of(ctx, rootNavigator: true).pop();
                  navigator.push(
                    MaterialPageRoute(
                      builder: (_) => WorkspaceEditorPage(novelId: novelId),
                    ),
                  );
                  return true;
                } catch (e) {
                  if (!ctx.mounted) return false;
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(const SnackBar(content: Text('创建小说失败')));
                  return false;
                }
              },
        ),
      ),
    );
  }

  Future<void> _quit() async {
    _log.checkpoint('tray quit selected');

    // 唤起窗口仅用于展示确认弹窗；窗口隐藏在托盘、或原生可见性校验失败时，
    // 都不能阻断退出——否则表现为"点了退出没反应"。
    BuildContext? ctx;
    try {
      await showMainWindow();
      ctx = navigatorKey.currentState?.context;
    } catch (error, stackTrace) {
      _log.warning(
        '[EXIT] show window before quit failed (non-fatal) '
        'error=$error\n$stackTrace',
      );
    }

    if (ctx != null && ctx.mounted) {
      bool confirmed = false;
      try {
        _log.checkpoint('tray quit opening confirmation');
        confirmed = await showConfirmDialog(
          ctx,
          title: '确认退出',
          message: '确定要退出吗？',
          confirmLabel: '退出',
          cancelLabel: '取消',
          variant: ConfirmDialogVariant.warning,
        );
        _log.checkpoint('tray quit confirmation result=$confirmed');
      } catch (error, stackTrace) {
        // 确认弹窗异常不应把退出流程一起拖住：视为未取消，继续走退出清理。
        _log.warning(
          '[EXIT] confirmation dialog failed; proceeding with shutdown '
          'error=$error\n$stackTrace',
        );
        confirmed = true;
      }
      if (confirmed != true) {
        _log.checkpoint('tray quit cancelled by user');
        return;
      }
    } else {
      _log.checkpoint('tray quit without mounted navigator; exiting directly');
    }

    await _exitApplication();
  }

  /// CrashSentinel 落盘失败不能阻断退出，统一降级为日志。
  void _safeMarkExit(String phase) {
    try {
      CrashSentinel.markActiveExitProgressSync(source: 'tray', phase: phase);
    } catch (error) {
      _log.warning('[EXIT] crash sentinel mark failed phase=$phase error=$error');
    }
  }

  /// guard 取消退出时必须让用户看到原因：此时窗口很可能正藏在托盘里，
  /// 静默 return 又会让用户以为"点了退出没反应"。
  Future<void> _notifyExitCancelled() async {
    if (!_initialized) return;
    try {
      await showMainWindow();
    } catch (error, stackTrace) {
      _log.warning(
        '[EXIT] show window for cancel notice failed error=$error\n$stackTrace',
      );
      return;
    }
    final context = navigatorKey.currentState?.context;
    if (context == null || !context.mounted) return;
    try {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('退出已取消：有内容正在保存，请稍后重试')),
      );
    } catch (error) {
      _log.warning('[EXIT] cancel notice failed error=$error');
    }
  }

  Future<void> _exitApplication({
    void Function(int)? terminate,
    FutureOr<void> Function()? unlock,
    Future<void> Function()? cleanExit,
    StartupFailureReporter? failureReporter,
  }) async {
    // 退出全流程兜底：任何一步抛异常都必须继续走到进程终止，
    // 否则托盘退出会卡在中间，同样表现为"点了没反应"。
    var proceed = true;
    try {
      final guards = List<Future<bool> Function()>.of(_exitGuards.reversed);
      for (var index = 0; index < guards.length; index++) {
        _log.checkpoint(
          'tray exit guard started index=$index count=${guards.length}',
        );
        var allowed = false;
        try {
          allowed = await guards[index]().timeout(
            _guardBudget,
            onTimeout: () {
              _log.warning(
                '[EXIT] guard timed out after ${_guardBudget.inSeconds}s; '
                'continuing shutdown',
              );
              return true;
            },
          );
        } catch (error, stackTrace) {
          _log.warning('[EXIT] guard failed error=$error\n$stackTrace');
          allowed = true;
        }
        _log.checkpoint(
          'tray exit guard completed index=$index allowed=$allowed',
        );
        if (!allowed) {
          proceed = false;
          break;
        }
      }
      if (!proceed) {
        _log.info('[EXIT] cancelled by guard');
        await _notifyExitCancelled();
        return;
      }


      _log.info('[EXIT] requested');
      _log.checkpoint('application exit requested (tray)');
      _safeMarkExit('requested');
      try {
        await windowManager.setPreventClose(false);
      } catch (error, stackTrace) {
        _log.warning(
          '[EXIT] setPreventClose(false) failed error=$error\n$stackTrace',
        );
      }

      // Close content databases first. Their normal close path can wait for
      // paused query streams; the process-exit path bypasses those listeners.
      _safeMarkExit('closing_content_databases');
      _log.info('[EXIT] closing content databases');
      try {
        await NovelContentDatabase.closeAllCachedForProcessExit();
      } catch (error, stackTrace) {
        _log.error(
          '[DB] table=novel_content_databases operation=CLOSE_ALL '
          'error=$error',
          error: error,
          stackTrace: stackTrace,
        );
      }
      _log.info('[EXIT] content databases closed');

      // Close databases before terminating to prevent NativeFinalizer SIGSEGV
      // during Dart isolate shutdown. The process-exit variant bypasses paused
      // Drift stream listeners while still awaiting the SQLite executor.
      _safeMarkExit('closing_app_database');
      _log.info('[EXIT] closing app database');
      try {
        await AppDatabase.closeCachedForProcessExit();
      } catch (error, stackTrace) {
        _log.error(
          '[DB] table=app_database operation=CLOSE_FOR_PROCESS_EXIT '
          'error=$error',
          error: error,
          stackTrace: stackTrace,
        );
      }
      _log.info('[EXIT] app database closed');

      // 正常退出：只清除当前会话 marker，待重试崩溃证据由 CrashSentinel 保留。
      // 必须在释放单实例锁之前完成，避免新进程看到旧 marker 或被旧进程删除。
      try {
        if (cleanExit != null) {
          await cleanExit();
        } else {
          CrashSentinel.markActiveSessionCleanExitSync();
        }
      } catch (error, stackTrace) {
        _log.warning('[EXIT] clean exit marker failed error=$error\n$stackTrace');
      }

      // await 锁释放：确保激活 server 关闭、端口文件删除后再退出，
      // 避免残留端口文件误导下一次启动的第二实例。
      try {
        await Future<void>.sync(unlock ?? SingleInstanceService.unlock)
            .timeout(const Duration(seconds: 3));
      } catch (error, stack) {
        _log.error(
          'Tray exit instance cleanup failed',
          error: error,
          stackTrace: stack,
        );
        try {
          await (failureReporter ?? StartupFailureReporter())
              .reportLifecycleFailure(
                phase: 'tray_exit',
                reason: error is TimeoutException
                    ? 'release_instance_timeout'
                    : 'release_instance_failed',
                error: error,
                stackTrace: stack,
              )
              .timeout(const Duration(seconds: 5));
        } catch (reportError) {
          _log.warning('Tray exit report did not finish: $reportError');
        }
      }

      // The tray plugin is native cleanup only; do not let its MethodChannel
      // reply prevent the process termination path on Windows.
      _log.info('[EXIT] hiding tray');
      // 托盘图标不清理干净会在任务栏留下"幽灵图标"，看起来像没退出。
      // 同步隐藏 + dispose，不等待原生回包，避免 MethodChannel 无响应卡死退出。
      try {
        _trayIcon?.setVisible(false);
      } catch (error, stackTrace) {
        _log.warning('tray hide failed error=$error\n$stackTrace');
      }
      _disposeTray();
      // close() only posts the native close request. Awaiting its MethodChannel
      // reply can strand exit if native window teardown stops the host loop.
      unawaited(
        windowManager.close().catchError((error, stackTrace) {
          _log.warning('window close request failed error=$error\n$stackTrace');
        }),
      );
    } catch (error, stackTrace) {
      _log.error(
        '[EXIT] unexpected shutdown failure error=$error',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (proceed) {
        _log.info('[EXIT] terminating');
        (terminate ?? exit)(0);
      }
    }
  }

  @visibleForTesting
  Future<void> exitApplicationForTesting(
    void Function(int) terminate, {
    FutureOr<void> Function()? unlock,
    Future<void> Function()? cleanExit,
    StartupFailureReporter? failureReporter,
  }) {
    return _exitApplication(
      terminate: terminate,
      unlock: unlock,
      cleanExit: cleanExit,
      failureReporter: failureReporter,
    );
  }
}

class _WindowCloseListener extends WindowListener {
  @override
  void onWindowClose() {
    // 区分"关窗最小化到托盘"与真正退出：关窗不退出进程，不应清除崩溃哨兵。
    _log.checkpoint('main window close intercepted; hiding to tray');
    Future.microtask(() async {
      await windowManager.hide();
    });
  }
}
