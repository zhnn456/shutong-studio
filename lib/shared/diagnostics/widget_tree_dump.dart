// 职责: 临时诊断工具 — 把当前 widget/render 树连同每个 RenderBox 的屏幕位置
//       写入临时文件，用于定位“肉眼可见但代码里找不到来源”的界面残留。
// 关联文件:
//   lib/main.dart（仅在 --dart-define=REVERIC_TREE_DUMP=1 时启用）

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

/// 每隔 [interval] 抓一次树，写到 [directory] 下的 reveric_tree_latest.txt，
/// 同时保留上一份快照。没有启用该开关时不要调用。
void startWidgetTreeDump({
  Duration interval = const Duration(seconds: 3),
  int maxLines = 40000,
  int maxDepth = 500,
}) {
  final file = File('${Directory.systemTemp.path}/reveric_tree_latest.txt');


  void dump() {
    try {
      final root = WidgetsBinding.instance.rootElement;
      if (root == null) {
        return;
      }
      final buffer = StringBuffer()
        ..writeln('=== ${DateTime.now().toIso8601String()} ===');
      var lines = 0;
      var deepest = 0;

      void walk(Element element, int depth) {
        if (lines >= maxLines || depth > maxDepth) {
          return;
        }
        lines++;
        if (depth > deepest) {
          deepest = depth;
        }
        try {
          final widget = element.widget;
          final renderObject = element.renderObject;
          var geometry = '';
          if (renderObject is RenderBox && renderObject.hasSize) {
            final origin = renderObject.localToGlobal(Offset.zero);
            geometry =
                ' @(${origin.dx.toStringAsFixed(1)},'
                '${origin.dy.toStringAsFixed(1)}) '
                '${renderObject.size.width.toStringAsFixed(1)}x'
                '${renderObject.size.height.toStringAsFixed(1)}';
          }
          var label = '';
          if (widget is Text && widget.data != null) {
            label = ' text="${widget.data!.replaceAll('\n', '\\n')}"';
          } else if (widget is RichText) {
            final text = widget.text.toPlainText().replaceAll('\n', '\\n');
            if (text.isNotEmpty) {
              label = ' rich="$text"';
            }
          }
          buffer.writeln('${widget.runtimeType}$geometry$label');
        } catch (error) {
          buffer.writeln('<读取失败: $error>');
        }
        try {
          element.visitChildren((child) => walk(child, depth + 1));
        } catch (error) {
          buffer.writeln('<子节点遍历失败: $error>');
        }
      }

      walk(root, 0);
      file.writeAsStringSync(
        '=== meta lines=$lines deepest=$deepest ===\n$buffer',
      );
    } catch (_) {
      // 诊断文件写失败不影响主流程。
    }
  }

  Timer.periodic(interval, (_) {
    try {
      dump();
    } catch (_) {
      // 单次失败跳过，下次再抓。
    }
  });
  WidgetsBinding.instance.addPostFrameCallback((_) => dump());
}
