// 职责: AI 快捷方式初始化 — 写入全局内置快捷方式默认配置，并按提示词版本升级旧条目。
// 关联文件:
//   lib/shared/models/ai_shortcut_action.dart
//   lib/shared/models/builtin_shortcut_prompts.dart
//   lib/shared/database/daos/ai_shortcut_action_dao.dart
//   lib/shared/services/app_initialization.dart
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/app_database.dart';
import '../../models/ai_shortcut_action.dart';

/// 已应用到本机的内置提示词版本；低于当前内置版本时触发一次升级。
const _builtinPromptRevisionKey = 'builtin_shortcut_prompt_revision';
const _builtinPromptRevision = 2;

/// 旧版（rev 1）的一句话提示词原文。
/// 只用于判断「用户是否手动改过这条内置提示词」：
/// 库里文本与旧版完全一致 → 视为没改过，可以安全升级；不一致 → 尊重用户版本，不覆盖。
const _legacyBuiltinPrompts = <String, String>{
  'outline_beat_generate_chapter_outlines':
      '请根据当前选中的节拍和所属大纲，生成这个节拍覆盖的所有章节大纲。',
  'chapter_generate_draft': '请根据当前章节的大纲、上下文和小说设定，生成这一章的正文草稿。',
  'chapter_polish': '请润色当前章节，保持原有剧情与作者声音，优化节奏、表达和细节。',
  'chapter_summarize': '请总结当前章节的关键剧情、人物变化、伏笔和后续需要注意的连续性问题。',
  'character_generate_arc':
      '请根据当前角色资料，设计或完善这个角色的成长弧光、关键选择和剧情作用。',
  'setting_expand':
      '请根据当前引用的设定条目扩写内容，补充可用于写作的细节、限制、冲突和剧情用途。',
  'foreshadowing_payoff_plan':
      '请根据当前伏笔，设计多个兑现方案，并说明每个方案的情绪效果、风险和适用章节。',
  'novel_generate_book_plan':
      '请根据当前小说简介，生成全书创作规划，包括核心卖点、结构、主要冲突、人物线和写作推进建议。',
};

Future<void> seedDefaultAiShortcutActions(AppDatabase database) async {
  final existing = await database.aiShortcutActionDao.getAll();
  final byBuiltinId = <String, AiShortcutAction>{};
  for (final action in existing) {
    final builtinId = action.builtinId;
    if (builtinId != null && builtinId.isNotEmpty) {
      byBuiltinId[builtinId] = action;
    }
  }

  final appliedRevision = await _readAppliedRevision();
  final now = DateTime.now();
  var sortOrder = existing.length;

  for (final seed in builtinAiShortcutActions) {
    final current = byBuiltinId[seed.id];

    // 1) 库里没有这条内置动作：首次安装，插入当前版本。
    if (current == null) {
      await database.aiShortcutActionDao.upsert(
        AiShortcutAction(
          id: 'builtin_${seed.id}',
          builtinId: seed.id,
          name: seed.name,
          prompt: seed.prompt,
          locations:
              seed.locations.map((location) => location.dbValue).toList(),
          enabled: seed.enabled,
          autoSend: seed.autoSend,
          sortOrder: sortOrder,
          createdAt: now,
          updatedAt: now,
          deletedAt: notDeletedSentinel,
        ),
      );
      sortOrder += 1;
      continue;
    }

    // 2) 已经是新版提示词：无需处理（幂等）。
    if (current.prompt == seed.prompt) continue;

    // 3) 本机已应用过这个版本：不重复覆盖。
    if (appliedRevision >= seed.promptRevision) continue;

    // 4) 用户手动改过（与旧版不一致）：保留用户版本，不覆盖。
    final legacyPrompt = _legacyBuiltinPrompts[seed.id];
    final userEdited = legacyPrompt != null && current.prompt != legacyPrompt;
    if (userEdited) continue;

    // 5) 仍是旧版且未改过：升级为完整提示词，名字与开关状态保持用户当前值。
    await database.aiShortcutActionDao.upsert(
      current.copyWith(prompt: seed.prompt, updatedAt: now),
    );
  }

  await _writeAppliedRevision();
}

Future<int> _readAppliedRevision() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_builtinPromptRevisionKey) ?? 1;
  } catch (_) {
    // prefs 不可用时按旧版本处理：仍执行一次"未改动即升级"，靠文本比对保证幂等。
    return 1;
  }
}

Future<void> _writeAppliedRevision() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_builtinPromptRevisionKey, _builtinPromptRevision);
  } catch (_) {
    // 写不进去只会导致下次重复比对，不会破坏用户数据。
  }
}
