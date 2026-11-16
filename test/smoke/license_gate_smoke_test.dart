// 职责: 冒烟测试 3 — 免费版门禁不可绕过（模型判定 + 服务层拦截 + 托盘菜单路径同源性）
//   以及 Keygate 授权 token 的本地验签强度。
// 关联文件:
//   lib/shared/models/license.dart（LicenseState / kFreeTierNovelLimit / NovelFreeLimitException）
//   lib/shared/services/license_service.dart（Keygate 激活）
//   lib/shared/services/keygate/keygate_token.dart（Ed25519 验签）
//   lib/shared/services/novel_actions.dart（创建前门禁判定）
//   lib/shared/services/system_tray_service.dart（托盘「新建小说」_newNovel）
//
// 说明:
//  - 授权验签测试用 cryptography 现场生成 Ed25519 密钥对签发 token，
//    不依赖真实服务器；伪造签名、改 payload、换设备标识都必须验签失败。
//  - 托盘 _newNovel 的对话框提交分支需要 NavigatorState，纯 flutter_test 下
//    只验证菜单点击进入 _newNovel 路径（先唤起主窗口）。

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/license.dart';
import 'package:reveric/shared/services/demo_novel.dart';
import 'package:reveric/shared/services/device_id_service.dart';
import 'package:reveric/shared/services/keygate/keygate_token.dart';
import 'package:reveric/shared/services/license_service.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_quota_gate.dart';
import 'package:reveric/shared/services/system_tray_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';

String _hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String _b64url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Future<({String token, String publicKeyHex})> _issueToken({
  required String deviceId,
  Map<String, Object?> overrides = const <String, Object?>{},
  Map<String, Object?> claimOverrides = const <String, Object?>{},
}) async {
  final keyPair = await Ed25519().newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final now = DateTime.now();
  final claims = <String, Object?>{
    'lid': 'lic_test',
    'pid': 'prod_test',
    'pln': 'Pro',
    'sts': 'active',
    'did': deviceId,
    'ftr': <String, Object?>{'tier': 'pro'},
    'iat': now.millisecondsSinceEpoch ~/ 1000,
    'exp': now.add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000,
    'grc': 3,
    ...claimOverrides,
  };
  final payload = _b64url(utf8.encode(jsonEncode(claims)));
  final signature = await Ed25519().sign(
    utf8.encode(payload),
    keyPair: keyPair,
  );
  final token = overrides['token'] as String? ??
      '$payload.${_b64url(signature.bytes)}';
  return (token: token, publicKeyHex: _hexOf(publicKey.bytes));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowManagerChannel = MethodChannel('window_manager');
  const trayManagerChannel = MethodChannel('tray_manager');
  final trayCalls = <String>[];

  late AppDatabase appDb;

  setUp(() {
    appDb = AppDatabase.forTest(NativeDatabase.memory());
    trayCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (call) async {
          trayCalls.add('window.${call.method}');
          if (call.method == 'isVisible') return true;
          if (call.method == 'isMinimized') return false;
          return true;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(trayManagerChannel, (call) async {
          trayCalls.add('tray.${call.method}');
          return true;
        });
  });

  tearDown(() async {
    await NovelContentDatabase.closeAllCached();
    await appDb.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(trayManagerChannel, null);
  });

  group('授权状态模型判定', () {
    test('免费版 isUsable == false；已激活但过期同样 isUsable == false', () {
      expect(const LicenseState.free().isFree, isTrue);
      expect(const LicenseState.free().isUsable, isFalse);

      final expired = LicenseState(
        tier: LicenseTier.standard,
        expiresAt: DateTime(2000),
      );
      expect(expired.isActivated, isTrue);
      expect(expired.isExpired, isTrue);
      expect(expired.isUsable, isFalse);
    });

    test('免费版小说额度常量为 1；激活后按服务端能力放开', () {
      expect(kFreeTierNovelLimit, 1);
      expect(const LicenseState.free().novelLimit, kFreeTierNovelLimit);
      final activated = LicenseState(
        tier: LicenseTier.pro,
        features: const <String, Object?>{'max_novels': '99'},
      );
      expect(activated.novelLimit, 99);
      expect(
        const LicenseState(tier: LicenseTier.pro).novelLimit,
        isNull,
        reason: '未下发额度的已激活授权视为不限',
      );
    });
  });

  group('Keygate token 本地验签（Ed25519）', () {
    test('合法 token 验签通过，claims 解析出套餐与设备标识', () async {
      final issued = await _issueToken(deviceId: 'device-a');
      final claims = await KeygateToken.verify(
        token: issued.token,
        publicKeyHex: issued.publicKeyHex,
        identifier: 'device-a',
      );
      expect(claims, isNotNull);
      expect(claims!.planName, 'Pro');
      expect(claims.deviceId, 'device-a');
      expect(claims.graceDays, 3);
      expect(claims.features['tier'], 'pro');
      expect(
        guessTier(planName: claims.planName, features: claims.features),
        LicenseTierGuess.pro,
      );
    });

    test('签名被篡改 → 验签失败', () async {
      final issued = await _issueToken(deviceId: 'device-a');
      final parts = issued.token.split('.');
      final forged = '${parts[0]}.${_b64url(utf8.encode('forged'))}';
      final claims = await KeygateToken.verify(
        token: forged,
        publicKeyHex: issued.publicKeyHex,
        identifier: 'device-a',
      );
      expect(claims, isNull);
    });

    test('payload 被替换（自签成 pro）→ 验签失败', () async {
      final issued = await _issueToken(deviceId: 'device-a');
      final payload = _b64url(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'lid': 'lic_fake',
            'did': 'device-a',
            'pln': 'Pro',
            'exp': DateTime.now()
                    .add(const Duration(days: 7))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
        ),
      );
      final tampered = '$payload.${issued.token.split('.')[1]}';
      final claims = await KeygateToken.verify(
        token: tampered,
        publicKeyHex: issued.publicKeyHex,
        identifier: 'device-a',
      );
      expect(claims, isNull);
    });

    test('token 属于另一台设备 → 验签失败（设备绑定生效）', () async {
      final issued = await _issueToken(deviceId: 'device-a');
      final claims = await KeygateToken.verify(
        token: issued.token,
        publicKeyHex: issued.publicKeyHex,
        identifier: 'device-b',
      );
      expect(claims, isNull);
    });

    test('公钥未配置时不做验签，直接判定未激活', () async {
      final issued = await _issueToken(deviceId: 'device-a');
      final claims = await KeygateToken.verify(
        token: issued.token,
        publicKeyHex: '',
        identifier: 'device-a',
      );
      expect(claims, isNull);
    });
  });

  group('授权码激活入口', () {
    test('内置服务器地址与 Ed25519 公钥已配置（否则激活会提示未配置）', () {
      expect(kKeygatePublicKeyHex, isNotEmpty);
      expect(kKeygatePublicKeyHex.length, anyOf(64, 88));
      expect(kKeygateBaseUrl, startsWith('https://'));
    });

    test('空授权码直接拒绝', () async {
      SharedPreferences.setMockInitialValues({});
      final result = await LicenseService.activate('   ');
      expect(result.isSuccess, isFalse);
      expect(result.message, 'settingsLicenseActivateFailed');
    });
  });

  group('门禁服务层不可绕过', () {
    test('已有 1 部小说的免费授权，createNovel 直接抛 NovelFreeLimitException', () async {
      SharedPreferences.setMockInitialValues({});
      await appDb.novelDao.create(
        id: 'gate_existing',
        title: '门禁既有作品',
        description: '',
      );
      final service = NovelActionsService(
        appDb,
        seedNovelWorkspace: (_) async {},
        seedScreenplayWorkspace: (_, _) async {},
        closeContentDatabase: (_) async {},
      );

      await expectLater(
        service.createNovel(title: '超额作品', description: ''),
        throwsA(isA<NovelFreeLimitException>()),
      );
      expect(await appDb.novelDao.getAll(), hasLength(1));
    });

    test('示例小说旁路同样被拦：已有 1 部作品时 createDemoNovel 抛 NovelFreeLimitException', () async {
      SharedPreferences.setMockInitialValues({});
      await appDb.novelDao.create(
        id: 'gate_existing_demo',
        title: '既有作品',
        description: '',
      );

      await expectLater(
        createDemoNovel(appDb),
        throwsA(isA<NovelFreeLimitException>()),
      );
      expect(await appDb.novelDao.getAll(), hasLength(1));
    });

    test('备份恢复旁路被拦：一次恢复 2 部作品超出免费额度', () async {
      SharedPreferences.setMockInitialValues({});
      await expectLater(
        NovelQuotaGate.ensureIncomingWithinLimit(2),
        throwsA(isA<NovelFreeLimitException>()),
      );
      // 1 部在额度内，不抛。
      await NovelQuotaGate.ensureIncomingWithinLimit(1);
    });

    test('设备标识与当前机器不同源时判为不一致（配置目录不能整包搬走）', () async {
      DeviceIdService.resetHardwareMatchCacheForTesting();
      SharedPreferences.setMockInitialValues({
        'device_id': 'a' * 64,
      });
      expect(await DeviceIdService().matchesCurrentHardware(), isFalse);
    });

    test('随机 UUID 形态的设备标识不参与同源判定（读不到硬件指纹的环境不误伤）', () async {
      DeviceIdService.resetHardwareMatchCacheForTesting();
      SharedPreferences.setMockInitialValues({
        'device_id': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
      });
      expect(await DeviceIdService().matchesCurrentHardware(), isTrue);
    });
  });

  group('托盘「新建小说」菜单路径', () {
    test('点击 newNovel 菜单项进入 _newNovel（先唤起主窗口），与服务层创建链路同源', () async {
      SharedPreferences.setMockInitialValues({});
      final tray = SystemTrayService();

      tray.onTrayMenuItemClick(
        MenuItem(key: 'newNovel', label: '新建小说'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(trayCalls, containsAllInOrder(['window.show', 'window.focus']));
    });
  });
}
