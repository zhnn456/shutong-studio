// 职责: 冒烟测试 5 — AI 调用失败分类到用户可读文案，不静默失败、不外抛原始异常。
// 关联文件:
//   lib/shared/models/ai_run_failure.dart（AiRunFailure / AiRunFailureKind）
//   lib/shared/localization/ai_run_failure_localization.dart（localizeAiRunFailure）
//   lib/shared/localization/locale_keys.dart
//
// 覆盖四类失败:
//   401（凭证无效）、429（限流）、超时/网络不可达、空回包（incompleteResponse）。
//
// 映射语义（与源码一致）:
//   - 无供应商原文时，HTTP 状态码走 _httpFailureLocaleKey 分支映射固定文案；
//   - 有供应商原文且未命中专用规则时，优先展示清洗后的原文（本地化为兜底）；
//   - 命中消息规则（如 api key not valid / concurrency limit）输出固定 key，不回显原文。
// 断言: 输出非空；不含 Exception / StackTrace 等调试文本；专用规则命中时不回显原文。

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/ai_run_failure_localization.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/models/ai_run_failure.dart';

void main() {
  // 测试环境不加载真实翻译包：identity 直接返回 locale key，便于断言分类结果。
  String identity(String key) => key;

  group('AI 失败 → 用户可读文案映射', () {
    test('401（无原文）→ 凭证/API Key 无效专用文案', () {
      const failure = AiRunFailure.http(statusCode: 401, providerId: 'openai');
      expect(localizeAiRunFailure(failure, identity), LocaleKeys.aiApiKeyInvalid);
    });

    test('429（无原文）→ 限流专用文案', () {
      const failure = AiRunFailure.http(statusCode: 429, providerId: 'anthropic');
      expect(localizeAiRunFailure(failure, identity), LocaleKeys.aiRateLimited);
    });

    test('超时/网络不可达 → 网络错误文案（network 终态）', () {
      const failure = AiRunFailure.network(providerId: 'gemini');
      expect(localizeAiRunFailure(failure, identity), LocaleKeys.aiNetworkError);
    });

    test('HTTP 408 → 请求超时文案', () {
      const failure = AiRunFailure.http(statusCode: 408, providerId: 'openai');
      expect(localizeAiRunFailure(failure, identity), LocaleKeys.aiRequestTimeout);
    });

    test('空回包（incompleteResponse）→ 响应不完整文案，不抛原始异常', () {
      const failure = AiRunFailure.incompleteResponse(providerId: 'openai');
      final label = localizeAiRunFailure(failure, identity);
      expect(label, LocaleKeys.aiIncompleteResponse);
      expect(label, isNotEmpty);
    });

    test('未识别的 5xx（无原文）→ 泛化请求失败文案，输出非空且不含调试文本', () {
      const failure = AiRunFailure.http(statusCode: 500, providerId: 'openai');
      final label = localizeAiRunFailure(failure, identity);
      expect(label, LocaleKeys.aiRequestFailed);
      expect(label, isNotEmpty);
      expect(label, isNot(contains('Exception')));
      expect(label, isNot(contains('StackTrace')));
    });

    test('命中消息规则时输出固定文案，不回显供应商原始错误消息', () {
      const invalidKey = AiRunFailure.http(
        statusCode: 401,
        providerMessage: 'api key not valid',
      );
      expect(
        localizeAiRunFailure(invalidKey, identity),
        LocaleKeys.aiApiKeyInvalid,
      );

      const concurrency = AiRunFailure.http(
        statusCode: 429,
        providerMessage: 'concurrency limit exceeded',
      );
      expect(
        localizeAiRunFailure(concurrency, identity),
        LocaleKeys.aiRateLimited,
      );
    });

    test('未命中规则的供应商原文仍展示为可读文本，且不泄漏调试堆栈', () {
      const failure = AiRunFailure.http(
        statusCode: 401,
        providerMessage: 'invalid api key',
      );
      final label = localizeAiRunFailure(failure, identity);
      expect(label, isNotEmpty);
      expect(label, isNot(contains('Exception')));
      expect(label, isNot(contains('StackTrace')));
    });
  });
}
