// 职责: AI 快捷方式模型 — 定义全局快捷方式、适用位置与内置默认。
// 关联文件:
//   lib/shared/providers/ai_shortcut_action_providers.dart
//   lib/shared/database/daos/ai_shortcut_action_dao.dart
//   lib/shared/database/app_database.dart

enum AiShortcutActionLocation {
  novel_description,
  chapter,
  outline,
  outline_beat,
  character,
  worldbuilding,
  material,
  skill_entry,
  item,
  faction,
  creature,
  foreshadowing;

  String get dbValue => name;

  static AiShortcutActionLocation? maybeFromDbValue(String value) {
    for (final location in values) {
      if (location.dbValue == value) {
        return location;
      }
    }
    return null;
  }
}

class AiShortcutActionDefinition {
  const AiShortcutActionDefinition({
    required this.id,
    required this.name,
    required this.prompt,
    required this.locations,
    this.builtinId,
    this.enabled = true,
    this.autoSend = false,
    this.sortOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? builtinId;
  final String name;
  final String prompt;
  final List<AiShortcutActionLocation> locations;
  final bool enabled;
  final bool autoSend;
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isBuiltin => builtinId != null && builtinId!.isNotEmpty;

  AiShortcutActionDefinition copyWith({
    String? id,
    String? builtinId,
    bool clearBuiltinId = false,
    String? name,
    String? prompt,
    List<AiShortcutActionLocation>? locations,
    bool? enabled,
    bool? autoSend,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AiShortcutActionDefinition(
      id: id ?? this.id,
      builtinId: clearBuiltinId ? null : (builtinId ?? this.builtinId),
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
      locations: locations ?? this.locations,
      enabled: enabled ?? this.enabled,
      autoSend: autoSend ?? this.autoSend,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class AiShortcutActionDraft {
  const AiShortcutActionDraft({
    required this.name,
    required this.prompt,
    required this.locations,
    this.enabled = true,
    this.autoSend = false,
  });

  final String name;
  final String prompt;
  final List<AiShortcutActionLocation> locations;
  final bool enabled;
  final bool autoSend;
}

class BuiltinAiShortcutAction {
  const BuiltinAiShortcutAction({
    required this.id,
    required this.name,
    required this.prompt,
    required this.locations,
    this.autoSend = false,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String prompt;
  final List<AiShortcutActionLocation> locations;
  final bool autoSend;
  final bool enabled;

  AiShortcutActionDefinition toDefinition({required int sortOrder}) {
    return AiShortcutActionDefinition(
      id: 'builtin_$id',
      builtinId: id,
      name: name,
      prompt: prompt,
      locations: locations,
      enabled: enabled,
      autoSend: autoSend,
      sortOrder: sortOrder,
    );
  }
}

const builtinAiShortcutActions = <BuiltinAiShortcutAction>[
  BuiltinAiShortcutAction(
    id: 'outline_beat_generate_chapter_outlines',
    name: '生成章纲',
    prompt: '请根据当前选中的节拍和所属大纲，生成这个节拍覆盖的所有章节大纲。',
    locations: [AiShortcutActionLocation.outline_beat],
  ),
  BuiltinAiShortcutAction(
    id: 'chapter_generate_draft',
    name: '生成正文',
    prompt: '请根据当前章节的大纲、上下文和小说设定，生成这一章的正文草稿。',
    locations: [AiShortcutActionLocation.chapter],
  ),
  BuiltinAiShortcutAction(
    id: 'chapter_polish',
    name: '润色本章',
    prompt: '请润色当前章节，保持原有剧情与作者声音，优化节奏、表达和细节。',
    locations: [AiShortcutActionLocation.chapter],
  ),
  BuiltinAiShortcutAction(
    id: 'chapter_summarize',
    name: '总结本章',
    prompt: '请总结当前章节的关键剧情、人物变化、伏笔和后续需要注意的连续性问题。',
    locations: [AiShortcutActionLocation.chapter],
  ),
  BuiltinAiShortcutAction(
    id: 'character_generate_arc',
    name: '生成角色弧光',
    prompt: '请根据当前角色资料，设计或完善这个角色的成长弧光、关键选择和剧情作用。',
    locations: [AiShortcutActionLocation.character],
  ),
  BuiltinAiShortcutAction(
    id: 'setting_expand',
    name: '扩写设定',
    prompt: '请根据当前引用的设定条目扩写内容，补充可用于写作的细节、限制、冲突和剧情用途。',
    locations: [
      AiShortcutActionLocation.worldbuilding,
      AiShortcutActionLocation.material,
      AiShortcutActionLocation.skill_entry,
      AiShortcutActionLocation.item,
      AiShortcutActionLocation.faction,
      AiShortcutActionLocation.creature,
    ],
  ),
  BuiltinAiShortcutAction(
    id: 'foreshadowing_payoff_plan',
    name: '设计兑现方案',
    prompt: '请根据当前伏笔，设计多个兑现方案，并说明每个方案的情绪效果、风险和适用章节。',
    locations: [AiShortcutActionLocation.foreshadowing],
  ),
  BuiltinAiShortcutAction(
    id: 'novel_generate_book_plan',
    name: '生成全书创作规划',
    prompt: '请根据当前小说简介，生成全书创作规划，包括核心卖点、结构、主要冲突、人物线和写作推进建议。',
    locations: [AiShortcutActionLocation.novel_description],
  ),
];

// ── 页面级 AI 创作入口（从整体思路出发构建，不依赖已选中的某一条目）──
const pageLevelAiShortcutActions = <AiShortcutActionDefinition>[
  AiShortcutActionDefinition(
    id: 'page_worldbuilding_create',
    name: '构建世界观',
    autoSend: true,
    locations: [AiShortcutActionLocation.worldbuilding],
    prompt: '''【角色定位】
你是这本书的世界观架构师。本条是「页面级 AI 创作」入口：不要依赖用户当前选中的某一条设定，而是从用户的整体创作思路出发，为这本书完整搭建一套自洽、可落地、能持续产剧的世界观体系。

【专业创作规则】
1. 分层构建，不要一上来就堆名词：按 地理与疆域 → 时代与技术/生产力水平 → 主要势力与组织 → 社会文化与信仰 → 核心规则体系（如修炼/魔法/科技系统）五层推进，每层先回答「它如何影响普通人的一天」。
2. 区分硬规则与软规则：硬规则是读者可以推理、可以预判结果的铁律（能量来源、使用条件、明确边界）；软规则负责神秘感与氛围，只用来制造问题，不要拿来解决问题。凡用规则破局的地方，规则必须事先写清楚。
3. 从代价出发设计规则，而不是从威力出发：先问「用一次要付出什么」——寿命、记忆、血债、稀缺材料、被某个存在记账。代价同时制造两难选择、经济体系和禁忌文化，让每次动用规则都成为一场戏而不是重置按钮。
4. 明确写出「不能做什么」：能力边界比能力本身更重要，列清楚该规则无法跨越的红线，避免后期机械降神。
5. 每个势力至少写清：利益诉求、控制的资源、与谁结盟、与谁为敌、内部矛盾——势力不是背景板，是冲突来源。
6. 主动制造结构性冲突：在资源稀缺、信仰对立、代际矛盾、阶层鸿沟里至少埋两条，让人物即使不动手也有张力。
7. 输出可直接落笔的写作细节，而不是百科词条：每个条目补 2-3 个感官化细节（街景、气味、器物、称呼、禁忌动作），方便正文直接调用。
8. 与人物和大纲联动：在相关条目末尾标注「这条设定最适合卡谁的脖子」「最适合在哪一章引爆」，为后续角色与大纲留接口。
9. 保持自洽：检查时间线、资源逻辑、势力实力对比是否互相打架，发现矛盾要主动指出并给修订方案。

【交互要求】
如果用户还没有给出具体的题材、时代、规则方向，先不要硬编，向用户提出 2-4 个关键问题收集设定（例如：题材与时代？想让读者对这个世界的第一印象是什么？最核心的一条规则/机制是什么？），等用户回答后再开始生成。生成时按条目拆分输出，每个设定条目独立成块，不要糊成一大段。

【落盘要求】
生成完成后，用你的内置工具把结果逐条写入世界观/设定库（/lore 或 /worldbuilding 集合）；如果存在条目级工具（如 CreateLocation、CreateFaction、CreateItem、CreateSkillEntry 等），按条目类型逐条创建，不要只在对话里贴文本。''',
  ),
  AiShortcutActionDefinition(
    id: 'page_character_create',
    name: '设定角色',
    autoSend: true,
    locations: [AiShortcutActionLocation.character],
    prompt: '''【角色定位】
你是这本书的人物导演。本条是「页面级 AI 创作」入口：不要围绕用户当前选中的某一个人物做修补，而是从用户的整体故事构思出发，搭建一套欲望清晰、缺陷成立、彼此咬合的人物阵容。

【专业创作规则】
1. 每个人物先写「伤口」与「渴望」：过去的伤口决定他如何看世界，当下的渴望驱动他采取行动；二者缺一，人物就是纸片。
2. 区分外在目标与内在需求：外在目标是他嘴上要的东西，内在需求是他自己都没意识到、必须被故事逼出来的成长；好故事让他最终意识到二者并不一致。
3. 写清他此刻深信的「谎」：人物开局都抱着一个关于自己或世界的错误信念（如「我只能靠自己」「示弱就是死」），整部书的弧光就是这条谎被现实反复击穿、最终被他主动放下或被他彻底吞掉的过程。
4. 缺陷必须与情节绑定：弱点不是性格标签，而是会在关键抉择里让他犯错、付出代价的那种缺陷；顺风顺水时显现不出来的缺陷不要写。
5. 规划弧光走向：明确是正向弧（从谎走向真相）、负向弧（被谎吞噬）还是平直弧（陪衬主角），并标出弧光的三个关键节点——信念被挑战、信念崩塌、做出最终选择。
6. 反派要给足「他自认为正义」的逻辑：写清他的诉求、他合理的一面、以及他与主角在价值观上的具体分歧，避免脸谱化。
7. 建关系网而不是孤人清单：每个人物至少标出 与主角的关系、与另一主要人物的关系、利益或情感上的牵连；关系之间要能互相制造冲突。
8. 绑定世界观：人物的身份、技艺、禁忌、口音、生活习惯必须长在已有的世界观上，不要让角色脱离设定悬浮。
9. 写可直接落笔的辨识度：补外貌的一两个记忆点、口头禅或语言习惯、习惯性小动作，让正文里三笔就能把这个人立起来。
10. 分清主角与配角功能：主角承担弧光与视角，关键配角各承担一个「逼主角成长」的剧情功能，功能重叠的配角要合并或差异化。

【交互要求】
如果用户还没说清故事要讲谁、要讲什么，先向用户提 2-4 个关键问题（例如：主角最想得到什么？他最怕面对什么？他与谁的对立最尖锐？这是成长向还是堕落向故事？），收集后再生成。生成时按人物逐条拆分，每个人物独立成块，不要混在一起。

【落盘要求】
生成完成后，用你的内置工具把每个人物逐条写入人物库（/characters 集合）；如果存在条目级工具（如 CreateCharacter 等），逐个人物创建，关系与弧光作为人物资料的一部分一并落库，不要只在对话里贴文本。''',
  ),
  AiShortcutActionDefinition(
    id: 'page_outline_create',
    name: '规划大纲',
    autoSend: true,
    locations: [AiShortcutActionLocation.outline],
    prompt: '''【角色定位】
你是这本书的结构编辑。本条是「页面级 AI 创作」入口：不要只把用户当前选中的某个节拍扩成章节，而是从整体构思出发，为这本书搭出全书骨架、分卷推进和逐章节奏。

【专业创作规则】
1. 先定全书结构比例：以三幕为骨架——建置约占四分之一、对抗升级约占中间一半、收束约占四分之一；关键节点按比例落位：激励事件、第一转折点、中点、至暗时刻、高潮、结局。
2. 长篇先分卷再拆章：明确每一卷的核心冲突、这一卷结束时人物必须发生的不可逆变化，以及卷末的大钩子。
3. 单章固定节奏模板：每章写清 ①本章目的（推进剧情/塑造人物/埋伏笔/掀悬念，只主打一个）②开篇钩子（危机、反常对话或悬而未决的画面，三行内抓人）③中段推进（事件、信息透露、人物交锋）④章末转折（反转、新危机或新疑问）。
4. 冲突逐级升级：每一场冲突的赌注要比上一场更高、退路更少，不要原地踏步重复同一强度的对抗。
5. 双线咬合：外在情节线与人物内心弧光线并行推进，外在事件恰好负责击穿人物那条「谎」，两条线在高潮处汇合。
6. 伏笔要建台账：每埋一条伏笔，标注埋设章节、计划兑现章节、兑现方式与情绪效果；同时标注哪些钩子是当卷回收、哪些是跨卷长线，避免烂尾或遗忘。
7. 钩子分层：开篇大钩钩住读者翻页，章末小钩钩住下一章，卷末大钩钩住下一卷；不要每章都用同一种钩子。
8. 张弛有度：高强度章节后安排缓冲章，用关系、日常或信息差调节节奏，避免读者持续紧绷后麻木。
9. 与已有设定对齐：检查大纲是否用得上已建立的世界观规则与人物缺陷，让规则和缺陷在关键抉择处真正「卡脖子」。

【交互要求】
如果用户还没说清这本书的核心卖点、篇幅预期和主角线，先提 2-4 个关键问题收集思路（例如：一句话故事是什么？计划多少万字/多少卷？高潮要落在什么抉择上？），再开始规划。输出按「全书结构 → 分卷 → 逐章清单」层级拆分，不要一坨输出。

【落盘要求】
生成完成后，用你的内置工具把大纲逐条写入大纲库（/outlines 集合）；如果存在条目级工具（如 CreateOutline 等），全书规划、分卷与章节大纲按层级逐条创建，伏笔登记一并落库，不要只在对话里贴文本。''',
  ),
  AiShortcutActionDefinition(
    id: 'page_chapter_create',
    name: '写作正文',
    autoSend: true,
    locations: [AiShortcutActionLocation.chapter],
    prompt: '''【角色定位】
你是这本书的执笔作者。本条是「页面级 AI 创作」入口：不要只对用户当前选中的某一段做润色，而是依据已有的大纲、世界观与人物设定，为对应章节完整写出可直接使用的正文草稿。

【专业创作规则】
1. 严格 show don't tell：不写「他很愤怒」，写他摔杯、话变短、指节发白这类可观察的动作与后果，让读者自己得出结论；情绪、氛围一律用动作、物件和行为证据呈现。
2. 调动五感而不是只写视觉：每场戏至少有一处听觉、嗅觉、触觉或味觉细节落地，避免全文只有画面的哑剧感。
3. 对话要有潜台词：人物嘴上说的和心里想的不一样，用停顿、答非所问、话题转移制造张力；能靠动作和环境交代的信息，不要让人物互相报简历。
4. 节奏靠句长控制：紧张处用短句、短段落加速；沉思、压抑或抒情处用长句放慢；段落之间留白换气，不要整章密不透风。
5. 视角全程一致：一章内锁定一个视角人物，只写他能看到、听到、想到的内容，不偷偷钻进别人脑子，不做全知旁白。
6. 与大纲严格对应：这一章的开篇钩子、中段推进、章末转折要与大纲条目一一咬合；该埋的伏笔、该击穿的人物信念，一个都不能漏。
7. 让人物用自己的声音说话：不同人物的句式、用词、口头禅要能区分，读者遮住名字也知道是谁在开口。
8. 场景先立坐标：开篇两三笔交代时空与环境状态，让读者立刻知道人在哪、刚发生了什么，再进冲突。
9. 拒绝信息倾倒：设定、前史通过当下的动作、争吵、误会逐步渗出，不要在场景中间插大段说明文字。
10. 章末留钩：在情绪或悬念的高点收束，抛出新的疑问或新的危机，让读者有翻下一章的冲动。

【写作流程（顺序执行，不可跳步）】
第 1 步 · 写前简报（先不要写正文）
先读取本章的章纲/大纲条目（如有）。若本章还没有章纲或仅有标题，先补一份简明章纲：本章目的（只主打一个）、卷入人物及各自状态、冲突/阻力、章末钩子。然后产出本章「场景清单」：列出 3-5 个场景，每个场景写清 时间地点、视角人物、本场目标推进、冲突/阻力、章末钩子。用列表输出场景清单，停下来等你确认或调整后再进入下一步。

第 2 步 · 起草正文
按确认后的场景清单逐段写正文，严格遵循上面的专业创作规则；只喂本章所需的上下文，不把整本书塞进来。

第 3 步 · 审查
正文完成后自查：① 是否与大纲条目和上一章结尾衔接；② 人物行为是否符合设定档案；③ 该埋/该收的伏笔是否到位；④ 是否存在"说明性对话、AI 腔"（如每段都以"突然/瞬间"开头、冲突同章即了）。输出简短审查结论与问题点，有问题先改。

第 4 步 · 沉淀（写后回填）
把本章产生的 角色状态变化、新伏笔、未解决线索、设定补充 整理成"待回填清单"（diff 形式：新增/变更项），列出来等你确认。确认后，用你的内置工具把这些改动回填到对应的人物库/大纲/设定库；未经确认不要改写已有设定。

【落盘要求】
按上述 4 步顺序推进，每一步与用户确认后再进入下一步，不要一口气输出所有步骤。正文落盘到 /chapters 集合对应章节；角色/大纲/设定的回填只在你确认后执行。''',
  ),
];
