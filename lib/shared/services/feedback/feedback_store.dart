// 职责: 客服留言会话的本地持久化与未读计数。
//   - 服务端只负责公开提交、后台回复；客户端用 SharedPreferences 保存本机留言会话，
//     离线也能看到自己的留言；联网后通过 check 接口把已回复条目同步回来。
//   - 未读回复通过 [FeedbackStore.unread] 全局通知侧边栏客服入口显示红点。
// 关联文件:
//   lib/shared/services/license_service.dart   （fetchFeedbackReplies / submitFeedback）
//   lib/shared/widgets/support/customer_service_feedback_dialog.dart
//   lib/desktop/pages/home.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 留言状态：待回复 / 已回复。与服务端 status 取值一致。
enum FeedbackStatus { open, replied }

String _statusName(FeedbackStatus status) =>
    status == FeedbackStatus.replied ? 'replied' : 'open';

FeedbackStatus _statusFromName(String? name) =>
    name == 'replied' ? FeedbackStatus.replied : FeedbackStatus.open;

/// 本机保存的一条留言会话（用户留言 + 客服回复）。
class FeedbackLocalMessage {
  const FeedbackLocalMessage({
    required this.id,
    required this.type,
    required this.content,
    required this.contact,
    required this.status,
    required this.createdAt,
    this.reply,
    this.repliedAt,
    this.seen = true,
    this.product,
    this.productName,
  });

  /// 服务端留言 ID；本地临时记录使用 `local-<uuid>`。
  final String id;
  final String type;
  final String content;
  final String contact;
  final FeedbackStatus status;
  final DateTime createdAt;
  final String? reply;
  final DateTime? repliedAt;

  /// 仅客户端本地状态：该留言的回复是否已被用户查看。
  final bool seen;

  /// 产品编码（writer / whale …），供后台区分软件来源；旧存档可能为空。
  final String? product;

  /// 产品展示名（书童AI写作 / 鲸喜AI …）。
  final String? productName;

  bool get hasReply => reply != null && reply!.trim().isNotEmpty;

  FeedbackLocalMessage copyWith({
    String? id,
    String? type,
    String? content,
    String? contact,
    FeedbackStatus? status,
    DateTime? createdAt,
    String? reply,
    DateTime? repliedAt,
    bool? seen,
    String? product,
    String? productName,
  }) {
    return FeedbackLocalMessage(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      contact: contact ?? this.contact,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      reply: reply ?? this.reply,
      repliedAt: repliedAt ?? this.repliedAt,
      seen: seen ?? this.seen,
      product: product ?? this.product,
      productName: productName ?? this.productName,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'content': content,
        'contact': contact,
        'status': _statusName(status),
        'reply': reply,
        'created_at': createdAt.toIso8601String(),
        'replied_at': repliedAt?.toIso8601String(),
        'seen': seen,
        'product': product,
        'product_name': productName,
      };

  factory FeedbackLocalMessage.fromJson(Map<String, dynamic> json) {
    return FeedbackLocalMessage(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'other',
      content: json['content'] as String? ?? '',
      contact: json['contact'] as String? ?? '',
      status: _statusFromName(json['status'] as String?),
      reply: json['reply'] as String?,
      createdAt: _parseTime(json['created_at']) ?? DateTime.now(),
      repliedAt: _parseTime(json['replied_at']),
      seen: json['seen'] == true,
      product: json['product'] as String?,
      productName: json['product_name'] as String?,
    );
  }

  /// 从服务端条目构造（check / messages 接口响应）。
  factory FeedbackLocalMessage.fromServer(Map<String, dynamic> json) {
    return FeedbackLocalMessage(
      id: json['id']?.toString() ?? '',
      type: json['type'] as String? ?? 'other',
      content: json['content'] as String? ?? '',
      contact: json['contact'] as String? ?? '',
      status: _statusFromName(json['status'] as String?),
      reply: json['reply'] as String?,
      createdAt: _parseTime(json['created_at']) ?? DateTime.now(),
      repliedAt: _parseTime(json['replied_at']),
      seen: false,
      product: json['product'] as String?,
      productName: json['product_name'] as String?,
    );
  }
}

DateTime? _parseTime(dynamic raw) {
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw);
  }
  return null;
}

/// 留言会话本地仓库（SharedPreferences，单 JSON 列表）。
class FeedbackStore {
  static const _key = 'feedback_thread_v1';

  /// 全局未读回复计数；侧边栏客服入口监听此值显示红点。
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);

  static Future<List<FeedbackLocalMessage>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return <FeedbackLocalMessage>[];
    }
    final List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return <FeedbackLocalMessage>[];
    }
    final messages = decoded
        .whereType<Map>()
        .map((e) => FeedbackLocalMessage.fromJson(e.cast<String, dynamic>()))
        .toList();
    messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    unread.value = _countUnread(messages);
    return messages;
  }

  /// 插入或更新一条本地留言；按 id 优先、其次内容去重。
  static Future<FeedbackLocalMessage> upsert(
    FeedbackLocalMessage message,
  ) async {
    final all = await loadAll();
    final existingIndex = all.indexWhere(
      (m) => m.id.isNotEmpty && m.id == message.id,
    );
    final index = existingIndex >= 0
        ? existingIndex
        : all.indexWhere(
            (m) => m.content == message.content && m.type == message.type,
          );
    if (index >= 0) {
      all[index] = all[index].copyWith(
        id: message.id.isEmpty ? null : message.id,
        reply: message.reply,
        repliedAt: message.repliedAt,
        status: message.status,
        seen: message.seen,
      );
    } else {
      all.add(message);
    }
    await _save(all);
    unread.value = _countUnread(all);
    return message;
  }

  /// 把服务端已回复条目合并进本地会话，返回本次新增的回复条数。
  ///
  /// 匹配顺序：服务端 id → 内容 + 类型。新拿到回复的旧留言标记为未读；
  /// 服务端存在而本地缺失的条目（换设备 / 重装）也补录进来。
  static Future<int> mergeReplies(List<Map<String, dynamic>> remote) async {
    final all = await loadAll();
    var newReplies = 0;

    for (final raw in remote) {
      final server = FeedbackLocalMessage.fromServer(raw);
      if (!server.hasReply) {
        continue;
      }
      final index = all.indexWhere(
        (m) => server.id.isNotEmpty && m.id == server.id,
      );
      final contentIndex = index < 0
          ? all.indexWhere(
              (m) => m.content == server.content && m.type == server.type,
            )
          : -1;
      final target = index >= 0 ? index : contentIndex;

      if (target >= 0) {
        final before = all[target];
        if (!before.hasReply) {
          newReplies += 1;
        }
        all[target] = before.copyWith(
          id: server.id.isEmpty ? null : server.id,
          reply: server.reply,
          repliedAt: server.repliedAt,
          status: FeedbackStatus.replied,
          seen: before.hasReply ? before.seen : false,
        );
      } else {
        all.add(server);
        newReplies += 1;
      }
    }

    await _save(all);
    unread.value = _countUnread(all);
    return newReplies;
  }

  /// 打开客服弹窗后清空未读标记。
  static Future<void> markAllSeen() async {
    final all = await loadAll();
    final updated = all.map((m) => m.seen ? m : m.copyWith(seen: true)).toList();
    await _save(updated);
    unread.value = 0;
  }

  static int _countUnread(List<FeedbackLocalMessage> messages) {
    return messages.where((m) => m.hasReply && !m.seen).length;
  }

  static Future<void> _save(List<FeedbackLocalMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(messages.map((m) => m.toJson()).toList());
    await prefs.setString(_key, encoded);
  }
}
