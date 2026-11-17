// 职责: 客服反馈弹窗 — 展示官方客服二维码与联系邮箱，并提供「投诉 / 建议 / 咨询 / 其他」的写留言功能。
// 留言直连 Keygate 后台提交；本机保存留言会话并同步客服回复，网络失败时在本机应用目录留档兜底。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/components/reveric_segmented_control.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/zh-CN/support.json
//   assets/translations/en/support.json
import 'dart:convert';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:reveric/shared/app_config.dart'
    show appVersion,
        revericFeedbackEmail,
        revericProductCode,
        revericProductName;
import 'package:reveric/shared/localization/app_localization.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/logger/app_logger.dart';
import 'package:reveric/shared/services/feedback/feedback_store.dart';
import 'package:reveric/shared/services/license_service.dart';
import 'package:reveric/shared/theme/theme.dart';
import '../../components/dialog_feedback.dart';
import '../../components/reveric_button.dart';
import '../../components/reveric_dialog.dart';
import '../../components/reveric_segmented_control.dart';
import '../../components/reveric_text_field.dart';

final _log = AppLogger.forModule('CustomerServiceFeedback');

/// 官方客服二维码资源路径。
const _customerServiceQrAsset = 'assets/images/customer_service_qr.jpg';

/// 展示/提交客服反馈的入口弹窗：官方客服二维码、联系邮箱与写留言表单。
Future<void> showCustomerServiceFeedbackDialog({
  required BuildContext context,
}) async {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);
  final dialogWidth = MediaQuery.sizeOf(context).width.clamp(320.0, 440.0) - 48;

  await showRevericDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _CustomerServiceFeedbackDialog(
        dialogContext: dialogContext,
        colors: colors,
        typo: typo,
        dialogWidth: dialogWidth,
      );
    },
  );
}

/// 留言类型；与 segmented control 的 segment value 对应。
enum _MessageType { complaint, suggestion, inquiry, other }

const _messageTypeValues = _MessageType.values;

class _CustomerServiceFeedbackDialog extends StatefulWidget {
  const _CustomerServiceFeedbackDialog({
    required this.dialogContext,
    required this.colors,
    required this.typo,
    required this.dialogWidth,
  });

  final BuildContext dialogContext;
  final RevericColors colors;
  final RevericTypography typo;
  final double dialogWidth;

  @override
  State<_CustomerServiceFeedbackDialog> createState() =>
      _CustomerServiceFeedbackDialogState();
}

class _CustomerServiceFeedbackDialogState
    extends State<_CustomerServiceFeedbackDialog> {
  late final TextEditingController _contentController;
  late final TextEditingController _contactController;
  _MessageType _selectedType = _MessageType.complaint;
  bool _submitting = false;
  bool _historyLoading = false;
  List<FeedbackLocalMessage> _history = <FeedbackLocalMessage>[];
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController();
    _contactController = TextEditingController();
    _loadHistory();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  /// 先展示本地会话，再联网同步已回复条目；打开弹窗即清掉未读红点。
  Future<void> _loadHistory() async {
    final local = await FeedbackStore.loadAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _history = local;
      _historyLoading = true;
    });
    await FeedbackStore.markAllSeen();

    final result = await LicenseService.fetchFeedbackReplies();
    if (!mounted) {
      return;
    }
    if (result.success) {
      final replies = _asMapList(result.data['replies']);
      if (replies.isNotEmpty) {
        await FeedbackStore.mergeReplies(replies);
        final merged = await FeedbackStore.loadAll();
        if (!mounted) {
          return;
        }
        setState(() => _history = merged);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _historyLoading = false);
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  String _typeLabelOf(BuildContext context, String name) {
    return switch (name) {
      'suggestion' => context.t(LocaleKeys.supportTypeSuggestion),
      'bug' || 'complaint' => context.t(LocaleKeys.supportTypeComplaint),
      'feedback' || 'inquiry' => context.t(LocaleKeys.supportTypeInquiry),
      _ => context.t(LocaleKeys.supportTypeOther),
    };
  }

  String _typeLabel(BuildContext context, _MessageType type) =>
      _typeLabelOf(context, type.name);

  String _formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  /// 留言直接提交到 Keygate 后台（不跳转邮件客户端）；
  /// 网络或服务端失败时在本机留档兜底，避免留言丢失。
  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      _showToast(
        context.t(LocaleKeys.supportEmptyMessage),
        DialogToastVariant.warning,
      );
      return;
    }
    if (_submitting) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _submitting = true);
    final contact = _contactController.text.trim();
    final typeLabel = _typeLabel(context, _selectedType);

    final result = await LicenseService.submitFeedback(
      type: _selectedType.name,
      content: content,
      contact: contact,
      appVersion: appVersion,
    );

    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);

    if (result.success) {
      final serverId = result.data['id']?.toString();
      final message = FeedbackLocalMessage(
        id: (serverId != null && serverId.isNotEmpty)
            ? serverId
            : 'local-${_uuid.v4()}',
        type: _selectedType.name,
        content: content,
        contact: contact,
        status: FeedbackStatus.open,
        createdAt: DateTime.now(),
        product: revericProductCode,
        productName: revericProductName,
      );
      await FeedbackStore.upsert(message);
      if (!mounted) {
        return;
      }
      final merged = await FeedbackStore.loadAll();
      setState(() {
        _history = merged;
        _contentController.clear();
      });
      messenger.showSnackBar(
        SnackBar(
          content: DialogToast(
            variant: DialogToastVariant.success,
            child: Text(context.t(LocaleKeys.supportSubmitSuccess)),
          ),
        ),
      );
      return;
    }

    // 提交失败：先在本机留档，联网后可由用户重新提交。
    await _saveMessageLocally(typeLabel, content, contact);
    messenger.showSnackBar(
      SnackBar(
        content: DialogToast(
          variant: DialogToastVariant.info,
          child: Text(context.t(LocaleKeys.supportSubmitFallbackSaved)),
        ),
      ),
    );
  }

  /// 把留言写成本地文本，落到应用目录的 support_messages 下。
  Future<void> _saveMessageLocally(
    String type,
    String content,
    String contact,
  ) async {
    try {
      final base = await getApplicationSupportDirectory();
      final folder = Directory(
        '${base.path}${Platform.pathSeparator}support_messages',
      );
      await folder.create(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[^0-9]'), '')
          .substring(0, 14);
      final file = File(
        '${folder.path}${Platform.pathSeparator}message_$stamp.txt',
      );
      await file.writeAsString(
        [
          '留言类型：$type',
          '联系方式：${contact.isEmpty ? '未填写' : contact}',
          '应用版本：v$appVersion',
          '',
          content,
        ].join('\n'),
        encoding: utf8,
      );
    } catch (error, stackTrace) {
      // 留档失败不阻断提交流程，只记录日志。
      _log.error(
        'save support message locally failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Widget _buildHistory(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.t(LocaleKeys.supportHistoryTitle),
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const Spacer(),
            if (_historyLoading)
              Text(
                context.t(LocaleKeys.supportHistoryLoading),
                style: typo.uiTiny.copyWith(color: colors.textMuted),
              ),
          ],
        ),
        const SizedBox(height: RevericSpacing.sm),
        if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: RevericSpacing.md),
            child: Text(
              context.t(LocaleKeys.supportHistoryEmpty),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
          )
        else
          for (final message in _history) ...[
            _buildHistoryItem(context, colors, typo, message),
            const SizedBox(height: RevericSpacing.sm),
          ],
      ],
    );
  }

  Widget _buildHistoryItem(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
    FeedbackLocalMessage message,
  ) {
    final replied = message.status == FeedbackStatus.replied && message.hasReply;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _historyChip(
                context,
                colors,
                typo,
                _typeLabelOf(context, message.type),
              ),
              const SizedBox(width: RevericSpacing.xs),
              _historyChip(
                context,
                colors,
                typo,
                replied
                    ? context.t(LocaleKeys.supportStatusReplied)
                    : context.t(LocaleKeys.supportStatusOpen),
              ),
              const Spacer(),
              Text(
                _formatTime(message.createdAt),
                style: typo.uiTiny.copyWith(color: colors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            message.content,
            style: typo.uiSmall.copyWith(
              color: colors.textPrimary,
              height: 1.5,
            ),
          ),
          if (message.contact.isNotEmpty) ...[
            const SizedBox(height: RevericSpacing.xxs),
            Text(
              message.contact,
              style: typo.uiTiny.copyWith(color: colors.textMuted),
            ),
          ],
          if (replied) ...[
            const SizedBox(height: RevericSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(RevericSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: BorderRadius.circular(RevericRadius.small),
                border: Border(
                  left: BorderSide(color: colors.border, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(LocaleKeys.supportReplyLabel),
                    style: typo.uiTiny.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: RevericSpacing.xxs),
                  Text(
                    message.reply!,
                    style: typo.uiSmall.copyWith(
                      color: colors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyChip(
    BuildContext context,
    RevericColors colors,
    RevericTypography typo,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.sm,
        vertical: RevericSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(RevericRadius.small),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: typo.uiTiny.copyWith(color: colors.textSecondary),
      ),
    );
  }

  Future<void> _openEmail() async {
    final uri = Uri.parse('mailto:$revericFeedbackEmail');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) {
        return;
      }
      _log.warning('mailto launch returned false');
    } catch (error, stackTrace) {
      _log.error(
        'mailto launch failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (mounted) {
      _showToast(
        context.t(
          LocaleKeys.supportOpenEmailFailed,
          namedArgs: {'email': revericFeedbackEmail},
        ),
        DialogToastVariant.error,
      );
    }
  }

  void _showToast(String message, DialogToastVariant variant) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: DialogToast(variant: variant, child: Text(message)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final typo = widget.typo;
    final contentWidth = widget.dialogWidth;

    return RevericDialog.panel(
      title: Text(context.t(LocaleKeys.supportTitle)),
      content: SizedBox(
        width: contentWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 官方客服二维码 + 可实现的功能说明
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(RevericSpacing.lg),
                decoration: BoxDecoration(
                  color: colors.surfaceDim,
                  borderRadius: BorderRadius.circular(RevericRadius.medium),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(RevericRadius.small),
                      child: Image.asset(
                        _customerServiceQrAsset,
                        width: 176,
                        height: 176,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                    const SizedBox(height: RevericSpacing.md),
                    Text(
                      context.t(LocaleKeys.supportQrTitle),
                      style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: RevericSpacing.xxs),
                    Text(
                      context.t(LocaleKeys.supportQrDescription),
                      textAlign: TextAlign.center,
                      style: typo.uiSmall.copyWith(
                        color: colors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: RevericSpacing.xl),
              // 写留言：类型选择 + 内容 + 联系方式
              Text(
                context.t(LocaleKeys.supportLeaveMessage),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: RevericSpacing.sm),
              RevericSegmentedControl<_MessageType>(
                segments: [
                  for (final type in _messageTypeValues)
                    RevericSegment(
                      value: type,
                      label: _typeLabel(context, type),
                    ),
                ],
                selected: _selectedType,
                onChanged: (type) => setState(() => _selectedType = type),
              ),
              const SizedBox(height: RevericSpacing.lg),
              RevericTextField(
                controller: _contentController,
                label: context.t(LocaleKeys.supportMessageLabel),
                hintText: context.t(LocaleKeys.supportMessagePlaceholder),
                helperText: context.t(
                  LocaleKeys.supportSubmitNote,
                  namedArgs: {'email': revericFeedbackEmail},
                ),
                multiline: true,
                minLines: 3,
                maxLines: 6,
              ),
              const SizedBox(height: RevericSpacing.lg),
              RevericTextField(
                controller: _contactController,
                label: context.t(LocaleKeys.supportContactLabel),
                hintText: context.t(LocaleKeys.supportContactHint),
              ),
              const SizedBox(height: RevericSpacing.xl),
              _buildHistory(context, colors, typo),
              const SizedBox(height: RevericSpacing.xl),
              // 联系邮箱
              InkWell(
                onTap: _openEmail,
                borderRadius: BorderRadius.circular(RevericRadius.medium),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.lg,
                    vertical: RevericSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceDim,
                    borderRadius: BorderRadius.circular(RevericRadius.medium),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      RevericIcon(
                        RevericIcons.envelope,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: RevericSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.t(LocaleKeys.supportContactEmail),
                              style: typo.uiTiny.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                            Text(
                              revericFeedbackEmail,
                              style: typo.uiSemibold.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      width: widget.dialogWidth + RevericSpacing.x4l * 2,
      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonClose),
          onPressed: () => Navigator.of(widget.dialogContext).pop(),
        ),
        RevericButton.primary(
          label: context.t(LocaleKeys.supportSubmit),
          loading: _submitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}
