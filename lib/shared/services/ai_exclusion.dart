// 职责: 「不进 AI 上下文」标记 — 作者可以点名某些设定不参与 AI 写作，其余照常用。
// 关联文件:
//   lib/shared/services/chapter_briefing_context.dart（构建上下文时按标记过滤）
//   lib/shared/widgets/character/character_tag_fields.dart（标签输入处给出提示）
//
// 为什么用标签而不是加字段：
//   角色/设定本来就有「标签」这栏，作者已经在用；加一个开关要动表结构、动迁移、
//   还要在每个编辑器里补 UI。用固定标签语义，写入路径零改动，过滤是确定性的代码，
//   不依赖模型自觉。
const String aiExclusionTag = '不进AI';

/// 兼容英文界面下作者手打的写法。
const Set<String> _aiExclusionAliases = {aiExclusionTag, 'no-ai', 'no_ai'};

bool isExcludedFromAi(Iterable<String>? tags) {
  if (tags == null) return false;
  for (final tag in tags) {
    if (_aiExclusionAliases.contains(tag.trim())) return true;
  }
  return false;
}
