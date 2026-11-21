// 回归测试：问卷挂起期间用户直接用新消息作答，不能被当成 "User cancelled"。
// 场景来源：2026-11-18 真机实测，聊天框回答被日志记成
// AgentToolSkipped reason=User cancelled，模型据此自行改了剧情走向。
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/ask_user_models.dart';
import 'package:reveric/shared/services/ai/pending_ask_user.dart';
import 'package:reveric/shared/services/ai/tool_error_normalize.dart';

PendingAskUser buildPending() {
  return PendingAskUser(
    request: const AskUserRequest(
      callId: 'call_1',
      questions: [
        AskUserQuestion(
          id: 'book_return',
          question: '第一章那本图集已经被她买走，第二章林渡为什么能翻它？',
          options: [
            AskUserOption(label: '民警老同学辨认后送回'),
            AskUserOption(label: '有人悄悄送回来'),
          ],
        ),
      ],
    ),
    runId: 1,
  );
}

void main() {
  test('新消息作答：结果不是取消，且带明确说明', () async {
    final pending = buildPending();
    pending.cancelForNewMessage(userText: '选A：民警老同学辨认');

    final result = await pending.future;
    expect(result.ok, isTrue);
    expect(result.cancelled, isFalse);
    expect(result.message, isNotNull);
    expect(result.message, contains('选A：民警老同学辨认'));
    expect(result.message, contains('不要视为取消'));

    // 走工具的归一化后仍然是成功结果，不会再出现 user_cancelled。
    final payload = normalizeToolFailureResult(result.toJson());
    expect(payload['ok'], isTrue);
    expect(payload['error_code'], isNull);
    expect(payload['error'], isNull);
    expect(payload['message'], contains('选A：民警老同学辨认'));
  });

  test('真正的取消：仍然保持 User cancelled 语义', () async {
    final pending = buildPending();
    pending.cancel();

    final result = await pending.future;
    expect(result.cancelled, isTrue);
    expect(result.ok, isFalse);

    final payload = normalizeToolFailureResult(result.toJson());
    expect(payload['ok'], isFalse);
    expect(payload['error_code'], 'user_cancelled');
  });

  test('新消息为空时不伪造回答内容，但语义仍是"新消息优先"', () async {
    final pending = buildPending();
    pending.cancelForNewMessage();

    final result = await pending.future;
    expect(result.ok, isTrue);
    expect(result.cancelled, isFalse);
    expect(result.message, contains('不要视为取消'));
  });
}
