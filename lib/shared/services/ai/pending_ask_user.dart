// 职责: 管理单次 AskUser 的等待截止、提醒与一次性完成。
// 关联文件:
//   lib/shared/models/ask_user_models.dart
//   lib/shared/services/ai/chat_turn_runner.dart
//   lib/shared/providers/ai_providers.dart
import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../models/ask_user_models.dart';

class PendingAskUser {
  PendingAskUser({
    required this.request,
    required this.runId,
    DateTime Function()? now,
    this.onReminder,
    this.onResolved,
  }) : _now = now ?? DateTime.now {
    startedAt = _now();
  }

  // 问卷卡挂起时 turn 不会结束，排队消息也就不会被消费（见
  // ChatSessionController._send 的互锁说明）。因此超时必须短到用户能接受：
  // 1 分钟提醒一次，5 分钟仍未回答即按"跳过本题"继续，避免出现长时间静默。
  static const reminderDelay = Duration(minutes: 1);
  static const timeout = Duration(minutes: 5);
  final String instanceId = const Uuid().v4();
  final AskUserRequest request;
  final int runId;
  final DateTime Function() _now;
  final void Function(PendingAskUser pending)? onReminder;
  final void Function(PendingAskUser pending, AskUserResult result)? onResolved;
  late final DateTime startedAt;
  final _completer = Completer<AskUserResult>();
  Timer? _reminderTimer;
  Timer? _timeoutTimer;
  bool _reminded = false;
  bool _started = false;

  String get blockId => 'askuser_${runId}_${instanceId}_${request.callId}';
  Future<AskUserResult> get future => _completer.future;
  bool get isCompleted => _completer.isCompleted;

  void start() {
    if (_started || isCompleted) {
      return;
    }
    _started = true;
    _reminderTimer = Timer(reminderDelay, checkDeadline);
    _timeoutTimer = Timer(timeout, checkDeadline);
    checkDeadline();
  }

  /// Also called on resume and before accepting a user response.
  void checkDeadline() {
    if (isCompleted) {
      return;
    }
    final elapsed = _now().difference(startedAt);
    if (elapsed >= timeout) {
      _resolve(AskUserResult.timeout(request.questions));
    } else if (elapsed >= reminderDelay && !_reminded) {
      _reminded = true;
      onReminder?.call(this);
    }
  }

  /// Rechecked after notification initialization and permission prompts.
  bool notificationIsCurrent({required bool reminder}) {
    if (isCompleted) {
      return false;
    }
    final elapsed = _now().difference(startedAt);
    return elapsed < timeout &&
        (reminder ? elapsed >= reminderDelay : elapsed < reminderDelay);
  }

  void complete(AskUserResult result) {
    checkDeadline();
    _resolve(result);
  }

  /// Run interruption is distinct from a user response and does not auto-select.
  void cancel() {
    _resolve(
      const AskUserResult(
        ok: false,
        cancelled: true,
        resolution: AskUserResolution.interrupted,
      ),
    );
  }

  /// 用户在问卷挂起期间直接发了新消息。
  ///
  /// 这不是"取消"：那条消息本身就是回答。这里返回 ok=true + 明确说明，
  /// 让模型把新消息当作用户的选择，而不是按 User cancelled 自行替你决定。
  void cancelForNewMessage({String? userText}) {
    final quoted = userText?.trim();
    _resolve(
      AskUserResult(
        ok: true,
        resolution: AskUserResolution.interrupted,
        message: quoted == null || quoted.isEmpty
            ? '用户没有点选问卷，而是直接发了新消息继续对话。'
                '请把随后那条用户消息视为对上述问题的回答，不要视为取消，也不要自行替用户决定。'
            : '用户没有点选问卷，而是直接发了新消息作答："$quoted"。'
                '请把这条消息视为对上述问题的回答，不要视为取消，也不要自行替用户决定。',
      ),
    );
  }

  void _resolve(AskUserResult result) {
    if (isCompleted) {
      return;
    }
    _reminderTimer?.cancel();
    _timeoutTimer?.cancel();
    _completer.complete(result);
    onResolved?.call(this, result);
  }
}
