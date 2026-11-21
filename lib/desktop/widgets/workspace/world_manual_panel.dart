// 职责: 「世界观手册」工作区页 — 六个标签（手册整理 / 阅读与图谱 / AI 分层 /
//       补齐设定 / 一致性 / 资料与版本）+ 世界观样本库入口。
//
// 口径（务必保持）：
//   * 页面里的势力 / 地点 / 人物数量来自现有实体表，不另建副本。
//   * AI 按钮走真实指令：把当前手册与该区块的已有内容作为参考送进对话，
//     并要求「只回写这一个区块」，不写库、不改正文。
//   * 一致性标签只展示能确定性判定的问题，不猜、不编。
//
// 关联文件:
//   lib/shared/services/world_manual.dart
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   assets/world_samples.json
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/models/novel_workspace.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/services/world_manual.dart';
import '../../../shared/theme/theme.dart';

/// 传给页面的实体摘要（只带名字与「有没有内容」，避免把整张表搬进 UI）。
class WorldEntityBrief {
  const WorldEntityBrief({required this.name, required this.hasContent});

  final String name;
  final bool hasContent;
}

class WorldManualPanel extends ConsumerStatefulWidget {
  const WorldManualPanel({
    super.key,
    required this.databasePath,
    required this.novelId,
    required this.novelTitle,
    required this.chapterCount,
    required this.factions,
    required this.locations,
    required this.characters,
    required this.unrecoveredForeshadowings,
    this.onAskAi,
  });

  final String? databasePath;
  final String novelId;
  final String novelTitle;
  final int chapterCount;
  final List<WorldEntityBrief> factions;
  final List<WorldEntityBrief> locations;
  final List<WorldEntityBrief> characters;
  final List<String> unrecoveredForeshadowings;

  /// 把「指令 + 参考」送进右侧对话。为空时按钮禁用，不假装能发。
  final void Function(String prompt, List<AiContextReference> references)? onAskAi;

  @override
  ConsumerState<WorldManualPanel> createState() => _WorldManualPanelState();
}

class _WorldManualPanelState extends ConsumerState<WorldManualPanel> {
  int _tab = 0;
  bool _loading = true;
  String? _savingNote;

  WorldManual _manual = const WorldManual();
  List<WorldManualVersionEntry> _versions = const [];
  List<WorldSample> _builtinSamples = const [];
  List<WorldSample> _userSamples = const [];

  late final TextEditingController _name;
  late final TextEditingController _tags;
  late final TextEditingController _oneLine;
  late final TextEditingController _readerGlimpse;
  late final TextEditingController _tone;
  late final TextEditingController _coreConflict;
  late final TextEditingController _rulesSummary;
  late final TextEditingController _rulesDetail;
  late final TextEditingController _factionsActive;
  late final TextEditingController _factionsPressure;
  late final TextEditingController _locationsAvailable;
  late final TextEditingController _locationsRisk;
  late final TextEditingController _tensionRelations;
  late final TextEditingController _tensionOutcome;

  List<TextEditingController> get _allControllers => [
    _name,
    _tags,
    _oneLine,
    _readerGlimpse,
    _tone,
    _coreConflict,
    _rulesSummary,
    _rulesDetail,
    _factionsActive,
    _factionsPressure,
    _locationsAvailable,
    _locationsRisk,
    _tensionRelations,
    _tensionOutcome,
  ];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _tags = TextEditingController();
    _oneLine = TextEditingController();
    _readerGlimpse = TextEditingController();
    _tone = TextEditingController();
    _coreConflict = TextEditingController();
    _rulesSummary = TextEditingController();
    _rulesDetail = TextEditingController();
    _factionsActive = TextEditingController();
    _factionsPressure = TextEditingController();
    _locationsAvailable = TextEditingController();
    _locationsRisk = TextEditingController();
    _tensionRelations = TextEditingController();
    _tensionOutcome = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _allControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(novelContentDatabaseProvider(widget.databasePath!));
    final manual = await readWorldManual(db);
    final versions = await listWorldManualVersions(db);
    final builtin = await loadBuiltinWorldSamples();
    final user = await listUserWorldSamples(db);
    final loaded = manual ?? WorldManual(name: widget.novelTitle);
    _applyToControllers(loaded);
    if (!mounted) return;
    setState(() {
      _manual = loaded;
      _versions = versions;
      _builtinSamples = builtin;
      _userSamples = user;
      _loading = false;
    });
  }

  void _applyToControllers(WorldManual manual) {
    _name.text = manual.name;
    _tags.text = manual.impressionTags;
    _oneLine.text = manual.oneLine;
    _readerGlimpse.text = manual.readerGlimpse;
    _tone.text = manual.tone;
    _coreConflict.text = manual.coreConflict;
    _rulesSummary.text = manual.rulesSummary;
    _rulesDetail.text = manual.rulesDetail;
    _factionsActive.text = manual.factionsActive;
    _factionsPressure.text = manual.factionsPressure;
    _locationsAvailable.text = manual.locationsAvailable;
    _locationsRisk.text = manual.locationsRisk;
    _tensionRelations.text = manual.tensionRelations;
    _tensionOutcome.text = manual.tensionOutcome;
  }

  WorldManual _draft() {
    String clip(String value) => value.length > worldManualFieldMaxCharacters
        ? value.substring(0, worldManualFieldMaxCharacters)
        : value;
    return WorldManual(
      name: _name.text.trim(),
      impressionTags: _tags.text.trim(),
      oneLine: clip(_oneLine.text.trim()),
      readerGlimpse: clip(_readerGlimpse.text.trim()),
      tone: clip(_tone.text.trim()),
      coreConflict: clip(_coreConflict.text.trim()),
      rulesSummary: clip(_rulesSummary.text.trim()),
      rulesDetail: clip(_rulesDetail.text.trim()),
      factionsActive: clip(_factionsActive.text.trim()),
      factionsPressure: clip(_factionsPressure.text.trim()),
      locationsAvailable: clip(_locationsAvailable.text.trim()),
      locationsRisk: clip(_locationsRisk.text.trim()),
      tensionRelations: clip(_tensionRelations.text.trim()),
      tensionOutcome: clip(_tensionOutcome.text.trim()),
      sampleId: _manual.sampleId,
    );
  }

  Future<void> _save({bool snapshot = false}) async {
    final db = ref.read(novelContentDatabaseProvider(widget.databasePath!));
    final draft = _draft();
    setState(() => _savingNote = '正在保存…');
    await saveWorldManual(db, draft, widget.novelTitle);
    var versions = _versions;
    if (snapshot) {
      await snapshotWorldManual(db, draft, '手动保存');
      versions = await listWorldManualVersions(db);
    }
    if (!mounted) return;
    setState(() {
      _manual = draft;
      _versions = versions;
      _savingNote = snapshot ? '已保存并记录版本' : '已保存';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(snapshot ? '已保存手册并记录一个版本' : '手册已保存')),
    );
  }

  void _ask(String prompt, String label) {
    final ask = widget.onAskAi;
    if (ask == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('右侧对话尚未就绪，稍后再试')),
      );
      return;
    }
    final text = _draft().composeText();
    ask(prompt, [
      AiContextReference.file(
        itemId: 'world_manual',
        label: label,
        content: text.isEmpty ? '（手册目前为空）' : text,
      ),
    ]);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已把「$label」送进右侧对话，回写只改这一个区块')),
    );
  }

  String _entityContext() {
    final buffer = StringBuffer();
    void dump(String label, List<WorldEntityBrief> items) {
      if (items.isEmpty) return;
      buffer.writeln('$label（共 ${items.length} 条）：${items.take(20).map((e) => e.name).join('、')}');
    }

    dump('已有势力', widget.factions);
    dump('已有地点', widget.locations);
    dump('已有角色', widget.characters);
    if (widget.unrecoveredForeshadowings.isNotEmpty) {
      buffer.writeln(
        '未回收伏笔（共 ${widget.unrecoveredForeshadowings.length} 条）：'
        '${widget.unrecoveredForeshadowings.take(12).join('、')}',
      );
    }
    if (widget.chapterCount > 0) {
      buffer.writeln('已有章节：${widget.chapterCount} 章');
    }
    return buffer.toString().trim();
  }

  String _blockPrompt(String block, String requirement) {
    final entities = _entityContext();
    return '请只整理世界观手册的「$block」区块，其他区块一律不动。\n'
        '$requirement\n'
        '硬性要求：\n'
        '1. 只用下面给出的已有设定做归纳，不要新造人名、地名、势力名；确实缺的可以留空并说明缺什么。\n'
        '2. 不要写解释性开场白，直接给可粘贴进该区块的正文。\n'
        '3. 语气克制，不用「震撼」「史诗」这类营销词。\n'
        '${entities.isEmpty ? '' : '\n$entities'}';
  }

  // ---------------------------------------------------------------------------
  // 视图
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    if (widget.databasePath == null) {
      return Center(
        child: Text(
          '书库尚未就绪，稍后再打开世界观手册。',
          style: RevericTheme.typographyOf(
            context,
          ).bodySmall.copyWith(color: colors.textMuted),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, colors),
        _buildTabs(context, colors),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  switch (_tab) {
                    0 => _buildArrangeTab(context, colors),
                    1 => _buildReadTab(context, colors),
                    2 => _buildLayerTab(context, colors),
                    3 => _buildFillTab(context, colors),
                    4 => _buildConsistencyTab(context, colors),
                    _ => _buildVersionTab(context, colors),
                  },
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, RevericColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _manual.name.trim().isEmpty
                      ? worldManualDefaultTitle
                      : _manual.name,
                  style: RevericTheme.typographyOf(context).heading2,
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.novelTitle} · 版本 ${_versions.isEmpty ? '未记录' : 'v${_versions.first.version}'}'
                  '${_savingNote == null ? '' : '　·　$_savingNote'}',
                  style: RevericTheme.typographyOf(
                    context,
                  ).uiSmall.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _openSampleLibrary(context),
            child: const Text('样本库'),
          ),
          const SizedBox(width: RevericSpacing.sm),
          OutlinedButton(
            onPressed: () => _save(snapshot: true),
            child: const Text('保存并记版本'),
          ),
          const SizedBox(width: RevericSpacing.sm),
          FilledButton(
            onPressed: () => _save(),
            child: const Text('保存手册'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(BuildContext context, RevericColors colors) {
    const labels = ['手册整理', '阅读与图谱', 'AI 分层', '补齐设定', '一致性', '资料与版本'];
    final issues = _collectIssues();
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            InkWell(
              onTap: () => setState(() => _tab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.lg,
                  vertical: RevericSpacing.md,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _tab == i ? colors.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labels[i],
                      style: RevericTheme.typographyOf(context).uiSmall.copyWith(
                        color: _tab == i ? colors.textPrimary : colors.textMuted,
                        fontWeight: _tab == i ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if ((i == 4 && issues.isNotEmpty) || (i == 3 && _collectGaps().isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: colors.warningBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${i == 4 ? issues.length : _collectGaps().length}',
                            style: RevericTheme.typographyOf(
                              context,
                            ).uiTiny.copyWith(color: colors.warningText),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- 标签 1：手册整理 -------------------------------------------------------

  Widget _buildArrangeTab(BuildContext context, RevericColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupTitle(context, colors, '整理世界手册',
            '先确认世界给读者的印象与核心矛盾，再按需整理规则、势力、地点和冲突张力。'),
        _impressionCard(context, colors),
        const SizedBox(height: RevericSpacing.x2l),
        _aiAssistRow(context, colors),
        const SizedBox(height: RevericSpacing.x3l),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumn = constraints.maxWidth > 760;
            final cards = [
              _blockCard(
                context,
                colors,
                title: '核心规则',
                hint: '规则限制力量、资源、禁忌和代价。',
                fieldA: ('规则总纲', _rulesSummary),
                fieldB: ('代表性规则', _rulesDetail),
                aiBlock: '核心规则',
                aiRequirement:
                    '归纳 3–5 条硬规则：谁受限制、限制什么、违反的代价是什么。每条一行，写清「规则名：内容」。',
              ),
              _blockCard(
                context,
                colors,
                title: '主要势力',
                hint: '势力决定角色归属、阵营压力和资源争夺。',
                fieldA: ('活跃势力', _factionsActive),
                fieldB: ('故事压力', _factionsPressure),
                aiBlock: '主要势力',
                aiRequirement:
                    '把已有势力按「谁掌什么、要什么、怕什么」写清，一行一个势力；然后写这些势力对主角构成的压力。',
              ),
              _blockCard(
                context,
                colors,
                title: '故事舞台',
                hint: '地点承载开局、升级、转折、决战。',
                fieldA: ('可用地点', _locationsAvailable),
                fieldB: ('进入风险', _locationsRisk),
                aiBlock: '故事舞台',
                aiRequirement:
                    '只写已有地点，一行一个，说明这个地点适合发生什么；再写进入该地点的风险或代价。',
              ),
              _blockCard(
                context,
                colors,
                title: '冲突张力',
                hint: '记势力关系、控制权与共同后果，让世界保持可写。',
                fieldA: ('势力关系', _tensionRelations),
                fieldB: ('共同后果', _tensionOutcome),
                aiBlock: '冲突张力',
                aiRequirement:
                    '写出两两势力之间「争什么」的关系，一行一组；再写这些冲突一旦爆发的共同后果。',
              ),
            ];
            if (twoColumn) {
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: RevericSpacing.x2l),
                      Expanded(child: cards[1]),
                    ],
                  ),
                  const SizedBox(height: RevericSpacing.x2l),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[2]),
                      const SizedBox(width: RevericSpacing.x2l),
                      Expanded(child: cards[3]),
                    ],
                  ),
                ],
              );
            }
            return Column(
              children: [
                for (final card in cards) ...[
                  card,
                  const SizedBox(height: RevericSpacing.x2l),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _impressionCard(BuildContext context, RevericColors colors) {
    return _card(
      colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('世界印象', style: RevericTheme.typographyOf(context).uiSmall.copyWith(color: colors.textMuted)),
              const Spacer(),
              Text(
                '标签用顿号或逗号分隔，会作为整体气质注入写章上下文',
                style: RevericTheme.typographyOf(context).uiTiny.copyWith(color: colors.textSubtle),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          _inlineField(colors, _tags, hint: '气象恢宏、衣冠楚楚、党争暗涌……', maxLines: 1),
          const SizedBox(height: RevericSpacing.x2l),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 700;
              final left = Column(
                children: [
                  _labeledField(context, colors, '一句话世界印象', _oneLine, 2),
                  const SizedBox(height: RevericSpacing.lg),
                  _labeledField(context, colors, '阅读气质', _tone, 2),
                ],
              );
              final right = Column(
                children: [
                  _labeledField(context, colors, '读者一眼', _readerGlimpse, 3),
                  const SizedBox(height: RevericSpacing.lg),
                  _labeledField(context, colors, '持续推动剧情的矛盾', _coreConflict, 3),
                ],
              );
              if (!wide) {
                return Column(children: [left, const SizedBox(height: RevericSpacing.lg), right]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: RevericSpacing.x3l),
                  Expanded(child: right),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _aiAssistRow(BuildContext context, RevericColors colors) {
    final buttons = <(String, String)>[
      ('世界概要', _blockPrompt('世界印象五段', '用已有内容把这五段写实：一句话世界印象、读者一眼、阅读气质、持续推动剧情的矛盾，以及 5–7 个印象标签。')),
      ('规则', _blockPrompt('核心规则', '归纳 3–5 条硬规则，写清谁受限制、违反的代价。')),
      ('势力', _blockPrompt('主要势力', '把已有势力按「谁掌什么、要什么、怕什么」写清，并归纳对主角的压力。')),
      ('地点', _blockPrompt('故事舞台', '只写已有地点，说明适合发生什么、进入的风险。')),
      ('张力', _blockPrompt('冲突张力', '写两两势力争什么，以及冲突爆发的共同后果。')),
      (
        '补齐选中区块',
        _blockPrompt(
          '当前光标所在区块',
          '清点下面四块里哪一块最空（核心规则 / 主要势力 / 故事舞台 / 冲突张力），只补最空的那一块，并说明为什么先补它。',
        ),
      ),
    ];
    return _card(
      colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI 辅助整理', style: RevericTheme.typographyOf(context).uiMedium),
                    const SizedBox(height: 2),
                    Text(
                      '每个按钮对应一个区块；AI 只回写该区块，不改正文、不建条目。',
                      style: RevericTheme.typographyOf(context).uiSmall.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: RevericSpacing.sm,
                runSpacing: RevericSpacing.sm,
                children: [
                  for (final item in buttons)
                    OutlinedButton(
                      onPressed: widget.onAskAi == null ? null : () => _ask(item.$2, item.$1),
                      child: Text(item.$1),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _blockCard(
    BuildContext context,
    RevericColors colors, {
    required String title,
    required String hint,
    required (String, TextEditingController) fieldA,
    required (String, TextEditingController) fieldB,
    required String aiBlock,
    required String aiRequirement,
  }) {
    return _card(
      colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: RevericTheme.typographyOf(context).uiMedium),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: RevericTheme.typographyOf(context).uiTiny.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: widget.onAskAi == null
                    ? null
                    : () => _ask(_blockPrompt(aiBlock, aiRequirement), '整理$title'),
                child: Text('整理$title'),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          _labeledField(context, colors, fieldA.$1, fieldA.$2, 4),
          const SizedBox(height: RevericSpacing.lg),
          _labeledField(context, colors, fieldB.$1, fieldB.$2, 4),
        ],
      ),
    );
  }

  // --- 标签 2：阅读与图谱 -----------------------------------------------------

  Widget _buildReadTab(BuildContext context, RevericColors colors) {
    final text = _draft().composeText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupTitle(context, colors, '阅读与图谱',
            '这是写章时会真正注入的手册正文；空白区块不会出现在这里，也不会污染上下文。'),
        _card(
          colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('手册正文', style: RevericTheme.typographyOf(context).uiSmall.copyWith(color: colors.textMuted)),
                  const Spacer(),
                  Text(
                    '约 ${text.length} 字',
                    style: RevericTheme.typographyOf(context).uiTiny.copyWith(color: colors.textSubtle),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  TextButton(
                    onPressed: text.isEmpty ? null : () => _ask(text, '手册正文'),
                    child: const Text('送入本轮对话'),
                  ),
                ],
              ),
              const SizedBox(height: RevericSpacing.sm),
              Container(
                padding: const EdgeInsets.all(RevericSpacing.lg),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  border: Border.all(color: colors.borderSubtle),
                ),
                constraints: const BoxConstraints(minHeight: 220),
                child: SelectableText(
                  text.isEmpty ? '手册还是空的。回到「手册整理」填五段印象，或从样本库套一个底子。' : text,
                  style: RevericTheme.typographyOf(context).bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: RevericSpacing.x2l),
        _card(
          colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('图谱摘要', style: RevericTheme.typographyOf(context).uiMedium),
              const SizedBox(height: RevericSpacing.sm),
              _kv(context, colors, '章节', '${widget.chapterCount} 章'),
              _kv(context, colors, '势力', '${widget.factions.length} 个${_names(widget.factions)}'),
              _kv(context, colors, '地点', '${widget.locations.length} 个${_names(widget.locations)}'),
              _kv(context, colors, '角色', '${widget.characters.length} 人${_names(widget.characters)}'),
              _kv(
                context,
                colors,
                '未回收伏笔',
                widget.unrecoveredForeshadowings.isEmpty
                    ? '无'
                    : '${widget.unrecoveredForeshadowings.length} 条：${widget.unrecoveredForeshadowings.take(6).join('、')}',
              ),
              const SizedBox(height: RevericSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '关系图与节点连线在左侧「实体关系」页维护，这里只读汇总。',
                  style: RevericTheme.typographyOf(context).uiTiny.copyWith(color: colors.textSubtle),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _names(List<WorldEntityBrief> items) {
    if (items.isEmpty) return '';
    return '：${items.take(8).map((e) => e.name).join('、')}';
  }

  // --- 标签 3：AI 分层 -------------------------------------------------------

  Widget _buildLayerTab(BuildContext context, RevericColors colors) {
    final layers = [
      (
        '世界层',
        '全书恒定：一句话印象、阅读气质、核心矛盾、核心规则。每章都注入，永不被裁剪。',
        _manual.oneLine.isNotEmpty || _manual.rulesSummary.isNotEmpty,
        '${_manual.oneLine.isNotEmpty ? '一句话印象 已填' : '一句话印象 空'}　'
            '${_manual.coreConflict.isNotEmpty ? '核心矛盾 已填' : '核心矛盾 空'}　'
            '${_manual.rulesSummary.isNotEmpty ? '规则总纲 已填' : '规则总纲 空'}',
      ),
      (
        '势力层',
        '按本章出场角色所属阵营带入，不是全书全塞。',
        widget.factions.isNotEmpty,
        '实体 ${widget.factions.length} 个；手册登记 ${splitNames(_manual.factionsActive).length} 项',
      ),
      (
        '舞台层',
        '只带本章发生在的地点，以及该地点的进入风险。',
        widget.locations.isNotEmpty,
        '实体 ${widget.locations.length} 个；手册登记 ${splitNames(_manual.locationsAvailable).length} 项',
      ),
      (
        '人物层',
        '带本章出场角色的档案与当前状态，不带全书角色表。',
        widget.characters.isNotEmpty,
        '角色 ${widget.characters.length} 人，其中 ${widget.characters.where((c) => c.hasContent).length} 人有小传',
      ),
      (
        '线索层',
        '只带「本章该埋 / 该收」的伏笔，不列全部。',
        widget.unrecoveredForeshadowings.isNotEmpty,
        '未回收 ${widget.unrecoveredForeshadowings.length} 条',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupTitle(context, colors, 'AI 分层',
            '这是写章时上下文的分层口径：越靠上越常驻，越靠下越按需。空白层不注入。'),
        for (final layer in layers) ...[
          _card(
            colors,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3,
                  height: 44,
                  color: layer.$3 ? colors.accent : colors.borderSubtle,
                ),
                const SizedBox(width: RevericSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(layer.$1, style: RevericTheme.typographyOf(context).uiMedium),
                          const SizedBox(width: RevericSpacing.sm),
                          Text(
                            layer.$3 ? '已就绪' : '待补',
                            style: RevericTheme.typographyOf(context).uiTiny.copyWith(
                              color: layer.$3 ? colors.success : colors.warningText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        layer.$2,
                        style: RevericTheme.typographyOf(context).uiSmall.copyWith(color: colors.textMuted),
                      ),
                      const SizedBox(height: 4),
                      Text(layer.$4, style: RevericTheme.typographyOf(context).uiTiny.copyWith(color: colors.textSubtle)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: RevericSpacing.lg),
        ],
      ],
    );
  }

  // --- 标签 4：补齐设定 -------------------------------------------------------

  List<({String title, String detail, String block, String requirement})> _collectGaps() {
    final gaps = <({String title, String detail, String block, String requirement})>[];
    final manual = _draft();
    void addIfEmpty(String title, String value, String block, String requirement) {
      if (value.trim().isNotEmpty) return;
      gaps.add((title: title, detail: '这一项空着，写手只能自由发挥。', block: block, requirement: requirement));
    }

    addIfEmpty('一句话世界印象', manual.oneLine, '世界印象五段', '写一句 30–60 字的世界印象。');
    addIfEmpty('阅读气质', manual.tone, '世界印象五段', '写 15–30 字的阅读气质。');
    addIfEmpty('核心矛盾', manual.coreConflict, '世界印象五段', '写一条能持续推动剧情的矛盾。');
    addIfEmpty('核心规则', manual.rulesSummary, '核心规则', '归纳 3–5 条硬规则。');
    addIfEmpty('活跃势力', manual.factionsActive, '主要势力', '写出势力与它们各自要什么。');
    addIfEmpty('可用地点', manual.locationsAvailable, '故事舞台', '写出可用地点与作用。');
    addIfEmpty('势力关系', manual.tensionRelations, '冲突张力', '写两两势力之间的关系。');

    final thinFactions = widget.factions.where((e) => !e.hasContent).toList();
    if (thinFactions.length >= 2) {
      gaps.add((
        title: '${thinFactions.length} 个势力只有名字',
        detail: '${thinFactions.take(5).map((e) => e.name).join('、')} 等条目没有内容，写手拿到的是空壳。',
        block: '主要势力',
        requirement: '为这些只有名字的势力各补一句「它掌什么、要什么」。',
      ));
    }
    final thinLocations = widget.locations.where((e) => !e.hasContent).toList();
    if (thinLocations.length >= 2) {
      gaps.add((
        title: '${thinLocations.length} 个地点只有名字',
        detail: '${thinLocations.take(5).map((e) => e.name).join('、')} 等条目没有描述。',
        block: '故事舞台',
        requirement: '为这些地点各补一句「这里会发生什么、进入的风险」。',
      ));
    }
    final thinCharacters = widget.characters.where((e) => !e.hasContent).toList();
    if (thinCharacters.length >= 2) {
      gaps.add((
        title: '${thinCharacters.length} 个角色没有小传',
        detail: '${thinCharacters.take(5).map((e) => e.name).join('、')} 等角色档案为空。',
        block: '人物层',
        requirement: '为这些角色补一句话身份与动机。',
      ));
    }
    return gaps;
  }

  Widget _buildFillTab(BuildContext context, RevericColors colors) {
    final gaps = _collectGaps();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupTitle(context, colors, '补齐设定',
            '按「缺了什么、为什么会飘」列出问题，每一项都能直接发指令补。'),
        if (gaps.isEmpty)
          _card(
            colors,
            child: Text(
              '手册与实体都没有明显缺口。接下来该盯的是章节里有没有偏离这些设定。',
              style: RevericTheme.typographyOf(context).bodySmall,
            ),
          )
        else
          for (final gap in gaps) ...[
            _card(
              colors,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(gap.title, style: RevericTheme.typographyOf(context).uiMedium),
                        const SizedBox(height: 2),
                        Text(
                          gap.detail,
                          style: RevericTheme.typographyOf(context).uiSmall.copyWith(color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onAskAi == null
                        ? null
                        : () => _ask(_blockPrompt(gap.block, gap.requirement), '补齐${gap.title}'),
                    child: const Text('发指令补'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: RevericSpacing.lg),
          ],
      ],
    );
  }

  // --- 标签 5：一致性 -------------------------------------------------------

  List<WorldManualIssue> _collectIssues() {
    final manual = _draftOrLoaded();
    if (manual.isBlank) {
      return const [
        WorldManualIssue(
          title: '手册还是空的',
          detail: '没有手册时，写章只能靠章纲自由发挥，最容易出基础错误。先去「手册整理」填，或从样本库套一个底子。',
          level: WorldManualIssueLevel.block,
        ),
      ];
    }
    final issues = <WorldManualIssue>[];
    if (!manual.impressionComplete) {
      issues.add(
        const WorldManualIssue(
          title: '五段印象没填全',
          detail: '一句话印象 / 读者一眼 / 阅读气质 / 核心矛盾 有空白，写手对世界的把握会漂。',
          level: WorldManualIssueLevel.warn,
          action: '补齐五段',
        ),
      );
    }
    if (!manual.blocksComplete) {
      issues.add(
        const WorldManualIssue(
          title: '四个区块有空白',
          detail: '规则 / 势力 / 地点 / 张力 有空白区块，对应内容写手只能自己编。',
          level: WorldManualIssueLevel.warn,
          action: '补齐区块',
        ),
      );
    }
    final nameDrift = checkNameDrift(
      manual: manual,
      factionNames: widget.factions.map((e) => e.name).toList(),
      locationNames: widget.locations.map((e) => e.name).toList(),
    );
    issues.addAll(nameDrift);

    // 手册标签与实体重复登记：同一势力在手册里登记两次，写手会当成两个。
    final duplicateFactions = _duplicatedNames(splitNames(manual.factionsActive));
    if (duplicateFactions.isNotEmpty) {
      issues.add(
        WorldManualIssue(
          title: '势力重复登记',
          detail: '「${duplicateFactions.join('、')}」在活跃势力里出现了两次以上。',
          level: WorldManualIssueLevel.hint,
          action: '去重',
        ),
      );
    }
    if (manual.rulesSummary.trim().isNotEmpty && manual.rulesDetail.trim().isEmpty) {
      issues.add(
        const WorldManualIssue(
          title: '只有规则总纲，没有代表性规则',
          detail: '总纲是口号，代表性规则才是写手能照着写的约束。',
          level: WorldManualIssueLevel.hint,
          action: '补代表性规则',
        ),
      );
    }
    if (widget.unrecoveredForeshadowings.length >= 5) {
      issues.add(
        WorldManualIssue(
          title: '${widget.unrecoveredForeshadowings.length} 条伏笔还没回收',
          detail: '到这里还不收，读者的耐心会先耗尽；在冲突张力里也没写它们的出口。',
          level: WorldManualIssueLevel.hint,
          action: '去伏笔分布看',
        ),
      );
    }
    return issues;
  }

  WorldManual _draftOrLoaded() {
    final draft = _draft();
    if (draft.isBlank && !_manual.isBlank) return _manual;
    return draft;
  }

  List<String> _duplicatedNames(List<String> names) {
    final seen = <String>{};
    final duplicated = <String>[];
    for (final name in names) {
      if (!seen.add(name)) {
        if (!duplicated.contains(name)) duplicated.add(name);
      }
    }
    return duplicated;
  }

  Widget _buildConsistencyTab(BuildContext context, RevericColors colors) {
    final issues = _collectIssues();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupTitle(context, colors, '一致性',
            '这里只报能确定性判定的问题：空项、名字对不上、重复登记、伏笔悬空。不做语义猜测。'),
        if (issues.isEmpty)
          _card(
            colors,
            child: Text('没有检出一致性问题。', style: RevericTheme.typographyOf(context).bodySmall),
          )
        else
          for (final issue in issues) ...[
            _card(
              colors,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: switch (issue.level) {
                        WorldManualIssueLevel.block => colors.deletionBg,
                        WorldManualIssueLevel.warn => colors.warningBg,
                        WorldManualIssueLevel.hint => colors.surfaceContainer,
                      },
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      switch (issue.level) {
                        WorldManualIssueLevel.block => '阻断',
                        WorldManualIssueLevel.warn => '提醒',
                        WorldManualIssueLevel.hint => '建议',
                      },
                      style: RevericTheme.typographyOf(context).uiTiny.copyWith(
                        color: switch (issue.level) {
                          WorldManualIssueLevel.block => colors.error,
                          WorldManualIssueLevel.warn => colors.warningText,
                          WorldManualIssueLevel.hint => colors.textMuted,
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(issue.title, style: RevericTheme.typographyOf(context).uiMedium),
                        const SizedBox(height: 2),
                        Text(
                          issue.detail,
                          style: RevericTheme.typographyOf(context).uiSmall.copyWith(color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (issue.action != null)
                    TextButton(
                      onPressed: widget.onAskAi == null
                          ? null
                          : () => _ask(
                              _blockPrompt('一致性修复：${issue.title}', '只针对这条问题给出可直接粘贴的修正，说明改哪一句、为什么改。'),
                              issue.action!,
                            ),
                      child: Text(issue.action!),
                    ),
                ],
              ),
            ),
            const SizedBox(height: RevericSpacing.lg),
          ],
      ],
    );
  }

  // --- 标签 6：资料与版本 ---------------------------------------------------

  Widget _buildVersionTab(BuildContext context, RevericColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupTitle(context, colors, '资料与版本',
            '每次「保存并记版本」都会留一份快照；改坏了能看出是哪几个字段变的，再手改回去。'),
        if (_versions.isEmpty)
          _card(
            colors,
            child: Text(
              '还没有版本快照。第一次点右上角「保存并记版本」，这里就会出现 v1。',
              style: RevericTheme.typographyOf(context).bodySmall,
            ),
          )
        else
          for (var i = 0; i < _versions.length; i++) ...[
            _card(
              colors,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_versions[i].note, style: RevericTheme.typographyOf(context).uiMedium),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatTime(_versions[i].createdAt)}　·　'
                          '${_versions[i].snapshot.composeText().length} 字'
                          '${i + 1 < _versions.length ? '　·　相比下一版改动：${_changedSummary(_versions[i], _versions[i + 1])}' : '　·　最早一版'}',
                          style: RevericTheme.typographyOf(context).uiTiny.copyWith(color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _restoreVersion(context, _versions[i]),
                    child: const Text('回到这一版'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: RevericSpacing.lg),
          ],
        const SizedBox(height: RevericSpacing.x2l),
        _card(
          colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('复用与共享', style: RevericTheme.typographyOf(context).uiMedium),
              const SizedBox(height: 2),
              Text(
                '把这套设定存成样本，下次开同题材的新书直接套用，不用重新铺世界。',
                style: RevericTheme.typographyOf(context).uiSmall.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: RevericSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: () => _saveAsSample(context),
                      child: const Text('存为我的样本'),
                    ),
                    const SizedBox(width: RevericSpacing.sm),
                    OutlinedButton(
                      onPressed: () => _openSampleLibrary(context),
                      child: const Text('打开样本库'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _changedSummary(WorldManualVersionEntry newer, WorldManualVersionEntry older) {
    final changed = newer.snapshot.diffFields(older.snapshot);
    if (changed.isEmpty) return '无';
    return changed.take(3).join('、') + (changed.length > 3 ? ' 等 ${changed.length} 项' : '');
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  Future<void> _restoreVersion(BuildContext context, WorldManualVersionEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('回到 ${entry.note}'),
        content: const Text('会用这一版覆盖当前编辑区，并把当前内容先存成一个版本，改坏了还能回来。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('回到这一版')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _save(snapshot: true);
    _applyToControllers(entry.snapshot);
    final db = ref.read(novelContentDatabaseProvider(widget.databasePath!));
    await saveWorldManual(db, entry.snapshot, widget.novelTitle);
    if (!mounted) return;
    setState(() => _manual = entry.snapshot);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已回到 ${entry.note}')));
  }

  Future<void> _saveAsSample(BuildContext context) async {
    final draft = _draft();
    if (draft.isBlank) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('手册是空的，先填内容再存样本')));
      return;
    }
    final nameController = TextEditingController(text: draft.name.trim().isEmpty ? widget.novelTitle : draft.name);
    final genreController = TextEditingController();
    final summaryController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('存为我的样本'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: '样本名')),
              const SizedBox(height: RevericSpacing.md),
              TextField(controller: genreController, decoration: const InputDecoration(labelText: '题材（如 历史 · 官场）')),
              const SizedBox(height: RevericSpacing.md),
              TextField(
                controller: summaryController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '一句话说明这套设定适合写什么'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('保存')),
        ],
      ),
    );
    if (saved != true) return;
    final db = ref.read(novelContentDatabaseProvider(widget.databasePath!));
    await saveWorldSampleFromManual(
      db,
      draft.copyWith(name: nameController.text.trim()),
      genreController.text.trim(),
      summaryController.text.trim(),
    );
    nameController.dispose();
    genreController.dispose();
    summaryController.dispose();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已存为我的样本')));
  }

  // --- 样本库 ---------------------------------------------------------------

  Future<void> _openSampleLibrary(BuildContext context) async {
    final builtin = _builtinSamples;
    final user = _userSamples;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colors = RevericTheme.colorsOf(dialogContext);
        return Dialog(
          child: SizedBox(
            width: 860,
            height: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('世界观样本库', style: RevericTheme.typographyOf(dialogContext).heading2),
                            const SizedBox(height: 2),
                            Text(
                              '套用只写手册与同名条目；书里已有的同名势力 / 地点不会重复建。',
                              style: RevericTheme.typographyOf(dialogContext).uiSmall.copyWith(color: colors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.borderSubtle),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    children: [
                      _sampleGroupTitle(dialogContext, colors, '内置样本（随包）'),
                      if (builtin.isEmpty)
                        Text('内置样本未加载。', style: RevericTheme.typographyOf(dialogContext).uiSmall),
                      for (final sample in builtin) ...[
                        _sampleTile(dialogContext, colors, sample),
                        const SizedBox(height: RevericSpacing.lg),
                      ],
                      const SizedBox(height: RevericSpacing.md),
                      _sampleGroupTitle(dialogContext, colors, '我的样本'),
                      if (user.isEmpty)
                        Text(
                          '还没有自建样本。在「资料与版本」把当前手册存为样本即可。',
                          style: RevericTheme.typographyOf(dialogContext).uiSmall.copyWith(color: colors.textMuted),
                        ),
                      for (final sample in user) ...[
                        _sampleTile(dialogContext, colors, sample, deletable: true),
                        const SizedBox(height: RevericSpacing.lg),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    await _load();
  }

  Widget _sampleGroupTitle(BuildContext context, RevericColors colors, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.sm),
      child: Text(text, style: RevericTheme.typographyOf(context).uiSmall.copyWith(color: colors.textMuted)),
    );
  }

  Widget _sampleTile(
    BuildContext context,
    RevericColors colors,
    WorldSample sample, {
    bool deletable = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderSubtle),
        color: colors.surfaceContainer,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sample.name, style: RevericTheme.typographyOf(context).uiMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${sample.genre.isEmpty ? '未标注题材' : sample.genre}　·　'
                      '势力 ${sample.manual.factionsActive.split(RegExp(r'[、，,]')).where((e) => e.trim().isNotEmpty).length} 项　·　'
                      '地点 ${sample.manual.locationsAvailable.split(RegExp(r'[、，,]')).where((e) => e.trim().isNotEmpty).length} 项',
                      style: RevericTheme.typographyOf(context).uiTiny.copyWith(color: colors.textSubtle),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _previewSample(context, sample),
                child: const Text('预览'),
              ),
              const SizedBox(width: RevericSpacing.xs),
              FilledButton(
                onPressed: () => _applySample(context, sample),
                child: const Text('套用到本书'),
              ),
              if (deletable) ...[
                const SizedBox(width: RevericSpacing.xs),
                TextButton(
                  onPressed: () => _deleteSample(context, sample),
                  child: const Text('删除'),
                ),
              ],
            ],
          ),
          if (sample.summary.trim().isNotEmpty) ...[
            const SizedBox(height: RevericSpacing.sm),
            Text(
              sample.summary,
              style: RevericTheme.typographyOf(context).uiSmall.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _previewSample(BuildContext context, WorldSample sample) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(sample.name),
        content: SizedBox(
          width: 640,
          height: 460,
          child: SingleChildScrollView(
            child: SelectableText(
              sample.manual.composeText(),
              style: RevericTheme.typographyOf(context).bodySmall,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _applySample(BuildContext context, WorldSample sample) async {
    final draftBlank = _draft().isBlank;
    if (!draftBlank) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('覆盖当前手册？'),
          content: const Text('套用会把整本手册换成这个样本的内容。当前内容会先存成一个版本，可以在「资料与版本」回到这一版。'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('套用')),
          ],
        ),
      );
      if (confirmed != true) return;
      await _save(snapshot: true);
    }
    final db = ref.read(novelContentDatabaseProvider(widget.databasePath!));
    final created = await applyWorldSample(db, sample, widget.novelTitle);
    _applyToControllers(sample.manual.copyWith(sampleId: sample.id));
    if (!mounted) return;
    setState(() => _manual = sample.manual);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(created == 0 ? '已套用样本（没有新建条目）' : '已套用样本，并新建 $created 个势力 / 地点条目')),
    );
  }

  Future<void> _deleteSample(BuildContext context, WorldSample sample) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除样本？'),
        content: Text('「${sample.name}」将从我的样本里移除，书里的手册不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(novelContentDatabaseProvider(widget.databasePath!));
    await deleteUserWorldSample(db, sample.id);
    await _load();
  }

  // --- 通用小组件 -----------------------------------------------------------

  Widget _groupTitle(BuildContext context, RevericColors colors, String title, String hint) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: RevericSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: RevericTheme.typographyOf(context).heading2),
          const SizedBox(height: 3),
          Text(hint, style: RevericTheme.typographyOf(context).uiSmall.copyWith(color: colors.textMuted)),
        ],
      ),
    );
  }

  Widget _card(RevericColors colors, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(RevericSpacing.x3l),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: child,
    );
  }

  Widget _labeledField(
    BuildContext context,
    RevericColors colors,
    String label,
    TextEditingController controller,
    int minLines,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: RevericTheme.typographyOf(context).uiTiny.copyWith(color: colors.textMuted)),
        const SizedBox(height: 4),
        _inlineField(colors, controller, minLines: minLines),
      ],
    );
  }

  Widget _inlineField(
    RevericColors colors,
    TextEditingController controller, {
    String? hint,
    int minLines = 2,
    int maxLines = 8,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      style: RevericTheme.typographyOf(context).bodySmall,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: RevericTheme.typographyOf(context).uiSmall.copyWith(color: colors.textSubtle),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.lg,
          vertical: RevericSpacing.md,
        ),
        border: OutlineInputBorder(borderSide: BorderSide(color: colors.borderSubtle)),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.borderSubtle)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.accent)),
      ),
    );
  }

  Widget _kv(BuildContext context, RevericColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: RevericTheme.typographyOf(context).uiTiny.copyWith(color: colors.textMuted)),
          ),
          Expanded(
            child: Text(value, style: RevericTheme.typographyOf(context).uiSmall.copyWith(color: colors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
