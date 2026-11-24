// 职责: 骨架完整性校验 — 判断一本书的 L2 骨架（世界观/角色/卷/章纲/梗概）是否齐、
//   引用是否闭合、已写正文是否沉淀，供概览页自检与「补下一卷」入口共用一套口径。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_overview.dart（自检清单展示）
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart（按卷补章）
//   assets/bundled_skills/setup/SKILL.md（L2 五段与自检 5 条）
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//
// 设计取舍:
//   1. 只做可判定的结构检查，不猜语义（例如"力量上限是否被突破"需要模型判断，
//      留给技能自检，不在代码里硬编码关键词匹配，避免误报把用户吓退）。
//   2. 问题按严重度分级：critical 阻塞开书，warning 影响质量，info 只是提醒。
//   3. 文案不在这里拼中文：返回 code + 计数，由 UI 走 LocaleKeys 渲染，遵守 i18n。
import '../database/novel_content_database.dart'
    show
        CharacterProfile,
        Document,
        Foreshadowing,
        characterRoleMinor,
        chapterStatDraft,
        chapterStatWriting,
        foreshadowingStatusPlanted,
        normalizeChapterStat;
import 'chapter.dart' show Chapter;
import 'novel_goal.dart' show NovelGoal;
import 'outline.dart' show OutlineDraft;

/// 问题严重度。
enum SkeletonIssueSeverity { critical, warning, info }

/// 问题类型。UI 按 code 取文案，新增 code 必须同步 locale key 与中英文案。
enum SkeletonIssueCode {
  worldMissing,
  worldThin,
  characterFew,
  characterThin,
  characterUnplaced,
  characterUnused,
  chapterMissing,
  outlineMissing,
  briefMissing,
  volumeMissing,
  foreshadowOpen,
  settlePending,
}

class SkeletonIssue {
  const SkeletonIssue({
    required this.code,
    required this.severity,
    this.count = 0,
    this.total = 0,
    this.firstId,
  });

  final SkeletonIssueCode code;
  final SkeletonIssueSeverity severity;

  /// 命中数量（如"7 张角色卡不完整"）。
  final int count;

  /// 参照总数（如"目标 120 章，已有 30 章"）。
  final int total;

  /// 跳转定位：章节 id 或角色 id；为空表示只能跳到板块。
  final String? firstId;
}

class SkeletonReport {
  const SkeletonReport({
    required this.issues,
    required this.passed,
    required this.total,
  });

  final List<SkeletonIssue> issues;
  final int passed;

  /// 参与检查的规则条数。
  final int total;

  int get criticalCount => issues
      .where((issue) => issue.severity == SkeletonIssueSeverity.critical)
      .length;

  int get warningCount => issues
      .where((issue) => issue.severity == SkeletonIssueSeverity.warning)
      .length;

  bool get isHealthy => issues.isEmpty;

  /// 有 critical 时不允许宣称"开书完成"。
  bool get isBlocked => criticalCount > 0;

  List<SkeletonIssue> get sorted => [...issues]
    ..sort((a, b) => a.severity.index.compareTo(b.severity.index));
}

/// 规则总数：改动规则必须同步这个数，否则 passed/total 会失真。
const int _skeletonRuleCount = 11;

/// 核心角色至少需要的数量（SKILL.md 的 L2 要求 6–8，低于 3 明显不成戏）。
const int _criticalCharacterCount = 3;
const int _fullCharacterCount = 6;

/// 世界观条目下限（L2 要求 5 条）。
const int _criticalWorldCount = 1;
const int _fullWorldCount = 5;

/// 超过这个章数仍未分卷，视为结构缺失。
const int _volumeRequiredChapterCount = 20;

/// 角色卡的合格线：6 个可直接映射的字段里至少填了 3 个。
/// 「怕什么 / 底线 / 能力 / 关系」没有独立列，约定写在 description 里，按 1 个字段计。
const int _characterFieldThreshold = 3;

SkeletonReport checkStorySkeleton({
  required List<Chapter> chapters,
  required List<CharacterProfile> characters,
  required List<Document> lore,
  required List<OutlineDraft> outlines,
  required List<Foreshadowing> foreshadowings,
  NovelGoal? goal,
}) {
  final issues = <SkeletonIssue>[];
  var passed = 0;

  final volumes = chapters.where((chapter) => chapter.isVolume).toList();
  final bodyChapters = chapters
      .where((chapter) => chapter.isNumberedChapter)
      .toList()
    ..sort((a, b) => (a.chapterNum ?? 0).compareTo(b.chapterNum ?? 0));

  // ── 世界观 ──────────────────────────────────────────────────────────
  if (lore.isEmpty) {
    issues.add(
      const SkeletonIssue(
        code: SkeletonIssueCode.worldMissing,
        severity: SkeletonIssueSeverity.critical,
      ),
    );
  } else if (lore.length < _fullWorldCount) {
    issues.add(
      SkeletonIssue(
        code: SkeletonIssueCode.worldThin,
        severity: SkeletonIssueSeverity.warning,
        count: lore.length,
        total: _fullWorldCount,
      ),
    );
  } else {
    passed++;
  }

  // ── 角色数量 ────────────────────────────────────────────────────────
  final coreCharacters = characters
      .where((profile) => profile.normalizedRole != characterRoleMinor)
      .where((profile) => profile.name.trim().isNotEmpty)
      .toList();
  if (coreCharacters.length < _criticalCharacterCount) {
    issues.add(
      SkeletonIssue(
        code: SkeletonIssueCode.characterFew,
        severity: SkeletonIssueSeverity.critical,
        count: coreCharacters.length,
        total: _fullCharacterCount,
        firstId: characters.isEmpty ? null : characters.first.id,
      ),
    );
  } else if (coreCharacters.length < _fullCharacterCount) {
    issues.add(
      SkeletonIssue(
        code: SkeletonIssueCode.characterFew,
        severity: SkeletonIssueSeverity.warning,
        count: coreCharacters.length,
        total: _fullCharacterCount,
      ),
    );
  } else {
    passed++;
  }

  // ── 角色卡完整度 ────────────────────────────────────────────────────
  final thinCharacters = coreCharacters.where((profile) {
    bool filled(String value) => value.trim().isNotEmpty;
    final mapped = [
      profile.identity,
      profile.personality,
      profile.motivation,
      profile.appearance,
      profile.arc,
      profile.description.trim().isNotEmpty
          ? profile.description
          : profile.biography,
    ].where(filled).length;
    return mapped < _characterFieldThreshold;
  }).toList();
  if (thinCharacters.isNotEmpty) {
    issues.add(
      SkeletonIssue(
        code: SkeletonIssueCode.characterThin,
        severity: SkeletonIssueSeverity.warning,
        count: thinCharacters.length,
        total: coreCharacters.length,
        firstId: thinCharacters.first.id,
      ),
    );
  } else {
    passed++;
  }

  // ── 首次登场未挂章 ──────────────────────────────────────────────────
  if (bodyChapters.isNotEmpty) {
    final unplaced = coreCharacters.where((profile) {
      final first = profile.firstAppearChapterId?.trim() ?? '';
      return first.isEmpty;
    }).toList();
    if (unplaced.isNotEmpty) {
      issues.add(
        SkeletonIssue(
          code: SkeletonIssueCode.characterUnplaced,
          severity: SkeletonIssueSeverity.info,
          count: unplaced.length,
          total: coreCharacters.length,
          firstId: unplaced.first.id,
        ),
      );
    } else {
      passed++;
    }
  } else {
    // 还没章节时不算问题，这一条不参与统计。
    passed++;
  }

  // ── 角色是否进过章纲 ────────────────────────────────────────────────
  if (bodyChapters.isNotEmpty && coreCharacters.isNotEmpty) {
    final haystack = bodyChapters
        .map((chapter) =>
            '${chapter.title ?? ''}\n${chapter.outline}\n${chapter.brief}')
        .join('\n');
    final unused = coreCharacters
        .where((profile) => profile.name.trim().length >= 2)
        .where((profile) => !haystack.contains(profile.name.trim()))
        .toList();
    if (unused.isNotEmpty) {
      issues.add(
        SkeletonIssue(
          code: SkeletonIssueCode.characterUnused,
          severity: SkeletonIssueSeverity.info,
          count: unused.length,
          total: coreCharacters.length,
          firstId: unused.first.id,
        ),
      );
    } else {
      passed++;
    }
  } else {
    passed++;
  }

  // ── 章数是否铺够 ────────────────────────────────────────────────────
  if (goal != null && goal.isUsable) {
    if (bodyChapters.length < goal.chapters) {
      issues.add(
        SkeletonIssue(
          code: SkeletonIssueCode.chapterMissing,
          severity: SkeletonIssueSeverity.warning,
          count: goal.chapters - bodyChapters.length,
          total: goal.chapters,
        ),
      );
    } else {
      passed++;
    }
  } else {
    // 没设目标时只检查"有没有章"。
    if (bodyChapters.isEmpty) {
      issues.add(
        const SkeletonIssue(
          code: SkeletonIssueCode.chapterMissing,
          severity: SkeletonIssueSeverity.critical,
        ),
      );
    } else {
      passed++;
    }
  }

  // ── 章纲缺失 ────────────────────────────────────────────────────────
  final missingOutline = bodyChapters
      .where((chapter) => chapter.outline.trim().isEmpty)
      .toList();
  if (missingOutline.isNotEmpty) {
    issues.add(
      SkeletonIssue(
        code: SkeletonIssueCode.outlineMissing,
        severity: SkeletonIssueSeverity.warning,
        count: missingOutline.length,
        total: bodyChapters.length,
        firstId: missingOutline.first.id,
      ),
    );
  } else {
    passed++;
  }

  // ── 梗概缺失（L2 新增要求，老数据普遍命中，所以只算 info） ──────────
  final missingBrief = bodyChapters
      .where((chapter) => chapter.brief.trim().isEmpty)
      .toList();
  if (missingBrief.isNotEmpty) {
    issues.add(
      SkeletonIssue(
        code: SkeletonIssueCode.briefMissing,
        severity: SkeletonIssueSeverity.info,
        count: missingBrief.length,
        total: bodyChapters.length,
        firstId: missingBrief.first.id,
      ),
    );
  } else {
    passed++;
  }

  // ── 卷结构（卷节点 + 卷级大纲轨道，缺任一侧都算未分卷） ─────────────
  final targetChapters = goal?.isUsable == true ? goal!.chapters : 0;
  final needsVolumes = bodyChapters.length >= _volumeRequiredChapterCount &&
      targetChapters >= _volumeRequiredChapterCount;
  if (needsVolumes && (volumes.isEmpty || outlines.isEmpty)) {
    issues.add(
      SkeletonIssue(
        code: SkeletonIssueCode.volumeMissing,
        severity: SkeletonIssueSeverity.warning,
        count: volumes.length,
        total: targetChapters,
      ),
    );
  } else {
    passed++;
  }

  // ── 伏笔：已埋未收 ──────────────────────────────────────────────────
  final openForeshadowings = foreshadowings.where((item) {
    if (item.status != foreshadowingStatusPlanted) return false;
    final payoff = item.payoffChapterId?.trim() ?? '';
    return payoff.isEmpty;
  }).toList();
  if (openForeshadowings.isNotEmpty) {
    issues.add(
      SkeletonIssue(
        code: SkeletonIssueCode.foreshadowOpen,
        severity: SkeletonIssueSeverity.warning,
        count: openForeshadowings.length,
        total: foreshadowings.length,
        firstId: openForeshadowings.first.id,
      ),
    );
  } else {
    passed++;
  }

  // ── 已写未沉淀（漂移起点） ──────────────────────────────────────────
  final unsettled = bodyChapters.where((chapter) {
    final written = chapter.wordCount > 0 || chapter.content.trim().isNotEmpty;
    if (!written) return false;
    final stat = normalizeChapterStat(chapter.stat);
    return stat == chapterStatDraft || stat == chapterStatWriting;
  }).toList();
  if (unsettled.isNotEmpty) {
    issues.add(
      SkeletonIssue(
        code: SkeletonIssueCode.settlePending,
        severity: SkeletonIssueSeverity.info,
        count: unsettled.length,
        total: bodyChapters.length,
        firstId: unsettled.first.id,
      ),
    );
  } else {
    passed++;
  }

  // 章纲轨道为空不单独报：上面「未分卷」已经覆盖同类缺口，重复报会让清单变吵。
  return SkeletonReport(
    issues: issues,
    passed: passed,
    total: _skeletonRuleCount,
  );
}

/// 便捷入口：直接从概览页已加载的数据算出报告。
SkeletonReport checkNovelSkeleton({
  required List<Chapter> chapters,
  required List<CharacterProfile> characterProfiles,
  required List<Document> worldbuildingEntries,
  required List<OutlineDraft> outlineEntries,
  required List<Foreshadowing> foreshadowings,
  NovelGoal? goal,
}) {
  return checkStorySkeleton(
    chapters: chapters,
    characters: characterProfiles,
    lore: worldbuildingEntries,
    outlines: outlineEntries,
    foreshadowings: foreshadowings,
    goal: goal,
  );
}
