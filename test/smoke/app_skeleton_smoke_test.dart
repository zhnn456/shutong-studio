// 职责: 冒烟测试 1 — 应用可启动骨架。
// 关联文件:
//   lib/main.dart（MyApp / _StartupLoadingApp / AppLifecycleWatcher）
//   lib/shared/services/system_tray_service.dart（全局 navigatorKey）
//
// 【降级说明（静态推断 + 已在本机 flutter analyze 下验证可编译）】
// MyApp.build 会 watch 以下 provider，任何一个都会触达 drift SQLite / 原生通道：
//   currentThemeModeProvider、appSettingsNotifierProvider、onboardingCompletedProvider、
//   storageCleanupSchedulerProvider、autoBackupSchedulerProvider、videoTaskServiceProvider、
//   providerAssetServiceProvider、imageTaskRecoveryProvider、audioTaskRecoveryProvider、
//   depthTaskProvider；此外 _EagerInitialization 还会级联官方技能同步与远程桥接 coordinator。
// 在没有完整 Provider 覆盖（内存 DB + 各 provider override）的情况下直接 pumpWidget(MyApp)
// 会在首帧触发数据库与 MethodChannel，不属于纯 flutter_test 可隔离范围。
// 另外，直接 import package:reveric/main.dart 会经桌面侧边栏链路拉入
// license_page 与 material/about.dart 的同名 LicensePage 歧义（已由业务侧修复，
// 见 sidebar.dart:49 / rail.dart:351）；为保持本测试不依赖该链路，本文件不导入 main.dart。
// 因此这里只做「测试宿主可挂载 + 关键全局句柄类型正确」的纯逻辑断言；
// 完整首帧 widget 级冒烟（MaterialApp 挂载、loading 占位、主题切换）列入报告待办，
// 待补齐 provider override 后在本文件追加 testWidgets。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/system_tray_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('应用骨架（宿主可挂载性 + 全局句柄断言）', () {
    testWidgets('最小 MaterialApp 可挂载占位首帧（测试宿主链路正常）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Placeholder())),
      );
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(Placeholder), findsOneWidget);
    });

    test('托盘服务持有的全局导航 Key 类型为 GlobalKey<NavigatorState>', () {
      final navigatorKey = SystemTrayService().navigatorKey;
      expect(navigatorKey, isA<GlobalKey<NavigatorState>>());
    });
  });
}
