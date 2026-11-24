/**
 * chinese-summary — 中文文本概要提取库
 *
 * TextRank + 位置加权 + TF-IDF 关键词加权 + MMR 多样性选句 + 多级压缩
 * 纯机器算法，无 AI 依赖，零外部依赖。
 * 使用字级 n-gram 绕过中文分词，位置先验提升首段/首句权重。
 *
 * Copyright (c) 2025 北京锋通科技有限公司
 * Authors: 郭玉峰, 吴琼
 * SPDX-License-Identifier: MIT
 *
 * 压缩级别（compressionLevel）：
 *   5 — 不压缩，返回全部句子
 *   4 — 轻度压缩，返回约 50% 句子
 *   3 — 中度压缩，返回约 30% 句子（默认，等价于 sentenceCount 模式）
 *   2 — 高度压缩，返回约 20% 句子 + 多轮重排
 *   1 — 极致压缩，子句级提取，压缩为一句话
 *
 * ─── 模块结构（升级指引） ───
 *
 * 本文件按流水线顺序组织，各段落的职责和修改指引如下：
 *
 *   类型定义        — 公共接口，修改 API 时从这里开始
 *   默认配置        — 调参入口，新增选项需同步修改 SummaryOptions + DEFAULT_OPTIONS + sanitizeOptions
 *   工具函数        — clampInt/Float/safeNumber，一般不需要修改
 *   1. 句子分割     — 分句规则，如需支持更多标点或语言，修改此段
 *   2. n-gram 提取  — 字级滑动窗口，如需词级 n-gram，替换此段
 *   2b. TF-IDF      — 关键词提取，如需换用其他关键词算法，替换此段
 *   3. 相似度计算   — n-gram 交集 / log 归一化，如需换相似度公式，修改此段
 *   4. 位置权重     — 首段/首句/段尾先验，如需新增位置规则，修改此段
 *   5. TextRank     — 核心迭代算法，如需换用 LexRank/LSA 等，替换此段
 *   6. 压缩映射     — 级别→句子数，如需调整各级压缩比例，修改此段
 *   6b. MMR 选句    — 多样性策略，如需换用其他去冗余算法，替换此段
 *   7. 子句分割     — 极致压缩专用，如需调整子句切分规则，修改此段
 *   8. 子句 TextRank — 极致压缩专用，一般不需要修改
 *   9. 多轮重排     — 高度压缩专用，如需调整重排策略，修改此段
 *   10. 极致压缩    — 子句提取+连词处理，如需调整拼接/连词逻辑，修改此段
 *   11. 主接口      — extractSummary / rankSentences，新增压缩级别时修改此段
 */

// ============================================================
// 类型定义
// ============================================================

/** 压缩级别 1-5 */
export type CompressionLevel = 1 | 2 | 3 | 4 | 5;

/** 概要提取选项 */
export interface SummaryOptions {
  /** 摘要句子数量，默认 3（与 compressionLevel 互斥，优先使用 compressionLevel） */
  sentenceCount?: number;
  /**
   * 压缩级别 1-5，默认 3
   *
   * 1 — 极致压缩：子句级提取，压缩为一句话
   * 2 — 高度压缩：约 20% 句子 + 多轮重排
   * 3 — 中度压缩：约 30% 句子（默认，等价于 sentenceCount=3）
   * 4 — 轻度压缩：约 50% 句子
   * 5 — 不压缩：返回全部句子
   *
   * 当同时指定 sentenceCount 和 compressionLevel 时，compressionLevel 优先
   */
  compressionLevel?: CompressionLevel;
  /** n-gram 大小，默认 2（bigram） */
  ngramSize?: number;
  /** TextRank 阻尼系数，默认 0.85 */
  dampingFactor?: number;
  /** 最大迭代次数，默认 30 */
  maxIterations?: number;
  /** 收敛阈值，默认 0.0001 */
  convergenceThreshold?: number;
  /** 位置权重：首段首句，默认 1.5 */
  weightFirstSentence?: number;
  /** 位置权重：首段其他句，默认 1.2 */
  weightFirstParagraph?: number;
  /** 位置权重：段落首句，默认 1.1 */
  weightParagraphStart?: number;
  /** 位置权重：段落末句，默认 1.05 */
  weightParagraphEnd?: number;
  /** 最小句子长度（字符数），默认 5 */
  minSentenceLength?: number;
  /** 最小子句长度（字符数），默认 3（仅 compressionLevel=1 时使用） */
  minClauseLength?: number;
  /** 极致压缩时最大子句数，默认 3（仅 compressionLevel=1 时使用） */
  maxClauses?: number;
  /**
   * MMR 多样性系数 λ，默认 0.7（仅 compressionLevel 2-4 时生效）
   *
   * λ 越大越偏向相关性（TextRank 得分），越小越偏向多样性
   * 取值范围 [0.3, 1.0]，设为 1.0 则退化为纯得分排序（关闭 MMR）
   */
  mmrLambda?: number;
  /**
   * 关键词权重系数，默认 1.2（0 表示关闭关键词加权）
   *
   * 包含全文关键词的句子，先验权重乘以此系数
   */
  keywordWeight?: number;
}

/** 句子信息 */
export interface SentenceInfo {
  /** 在全文中的序号 */
  index: number;
  /** 句子文本 */
  text: string;
  /** 所在段落序号 */
  paragraphIndex: number;
  /** 段落内句子序号 */
  sentenceInParagraph: number;
  /** 是否为段落首句 */
  isParagraphStart: boolean;
  /** 是否为段落末句 */
  isParagraphEnd: boolean;
  /** 是否为首段 */
  isFirstParagraph: boolean;
  /** TextRank 得分 */
  score: number;
}

/** 子句信息（compressionLevel=1 时使用） */
export interface ClauseInfo {
  /** 子句文本 */
  text: string;
  /** 来源句子序号 */
  sourceSentenceIndex: number;
  /** 在来源句子中的序号 */
  clauseIndex: number;
  /** 是否为句子的主干子句（第一个子句） */
  isMainClause: boolean;
  /** TextRank 得分 */
  score: number;
}

/** 概要提取结果 */
export interface SummaryResult {
  /** 摘要句子（按原文顺序排列） */
  summary: string[];
  /** 所有句子及其得分 */
  sentences: SentenceInfo[];
  /** 摘要文本（句子之间用空格连接） */
  text: string;
  /** 使用的压缩级别 */
  compressionLevel: CompressionLevel;
  /** 子句信息（仅 compressionLevel=1 时有值） */
  clauses?: ClauseInfo[];
}

// ============================================================
// 默认配置
// ============================================================

const DEFAULT_OPTIONS: Required<SummaryOptions> = {
  sentenceCount: 3,
  compressionLevel: 3,
  ngramSize: 2,
  dampingFactor: 0.85,
  maxIterations: 30,
  convergenceThreshold: 0.0001,
  weightFirstSentence: 1.5,
  weightFirstParagraph: 1.2,
  weightParagraphStart: 1.1,
  weightParagraphEnd: 1.05,
  minSentenceLength: 5,
  minClauseLength: 3,
  maxClauses: 3,
  mmrLambda: 0.7,
  keywordWeight: 1.2,
};

// ============================================================
// 工具函数
// ============================================================

/** 安全整数：将值限制在 [min, max] 范围内 */
function clampInt(value: unknown, min: number, max: number, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.max(min, Math.min(max, Math.floor(value)));
}

/** 安全浮点数：将值限制在 [min, max] 范围内 */
function clampFloat(value: unknown, min: number, max: number, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.max(min, Math.min(max, value));
}

/** 安全压缩级别 */
function sanitizeCompressionLevel(value: unknown): CompressionLevel {
  if (typeof value === "number" && Number.isFinite(value)) {
    const clamped = Math.max(1, Math.min(5, Math.floor(value)));
    return clamped as CompressionLevel;
  }
  return 3;
}

/** 标准化选项参数，确保所有值都在合法范围内 */
function sanitizeOptions(options: SummaryOptions): Required<SummaryOptions> {
  return {
    sentenceCount: clampInt(options.sentenceCount, 1, 100, DEFAULT_OPTIONS.sentenceCount),
    compressionLevel: sanitizeCompressionLevel(options.compressionLevel),
    ngramSize: clampInt(options.ngramSize, 1, 5, DEFAULT_OPTIONS.ngramSize),
    dampingFactor: clampFloat(options.dampingFactor, 0.1, 0.95, DEFAULT_OPTIONS.dampingFactor),
    maxIterations: clampInt(options.maxIterations, 1, 200, DEFAULT_OPTIONS.maxIterations),
    convergenceThreshold: clampFloat(options.convergenceThreshold, 1e-8, 1, DEFAULT_OPTIONS.convergenceThreshold),
    weightFirstSentence: clampFloat(options.weightFirstSentence, 0.5, 5, DEFAULT_OPTIONS.weightFirstSentence),
    weightFirstParagraph: clampFloat(options.weightFirstParagraph, 0.5, 5, DEFAULT_OPTIONS.weightFirstParagraph),
    weightParagraphStart: clampFloat(options.weightParagraphStart, 0.5, 5, DEFAULT_OPTIONS.weightParagraphStart),
    weightParagraphEnd: clampFloat(options.weightParagraphEnd, 0.5, 5, DEFAULT_OPTIONS.weightParagraphEnd),
    minSentenceLength: clampInt(options.minSentenceLength, 1, 100, DEFAULT_OPTIONS.minSentenceLength),
    minClauseLength: clampInt(options.minClauseLength, 1, 50, DEFAULT_OPTIONS.minClauseLength),
    maxClauses: clampInt(options.maxClauses, 1, 20, DEFAULT_OPTIONS.maxClauses),
    mmrLambda: clampFloat(options.mmrLambda, 0.3, 1.0, DEFAULT_OPTIONS.mmrLambda),
    keywordWeight: clampFloat(options.keywordWeight, 0, 5, DEFAULT_OPTIONS.keywordWeight),
  };
}

/** 安全数值：确保不为 NaN 或 Infinity */
function safeNumber(value: number, fallback: number = 0): number {
  return Number.isFinite(value) ? value : fallback;
}

// ============================================================
// 1. 句子分割
// ============================================================

/** 中文句子结束标点 */
const SENTENCE_ENDINGS = /[。！？；\n\r]/;
/** 中文引号/括号（可能跟在句末标点后） */
const TRAILING_QUOTES = /[」』""”）】》'']/;

/**
 * 将中文文本分割为句子数组
 *
 * 规则：
 * - 遇到 。！？；\n 视为句子结束
 * - 句末标点后的引号/括号归入前一句
 * - 连续换行视为段落分隔
 */
function splitSentences(text: string, minLength: number): SentenceInfo[] {
  const sentences: SentenceInfo[] = [];

  // 先按段落分割（连续换行或单个换行）
  const paragraphs = text.split(/[\n\r]+/).filter((p) => p.trim().length > 0);

  let globalIndex = 0;

  for (let pi = 0; pi < paragraphs.length; pi++) {
    const para = paragraphs[pi].trim();
    if (para.length === 0) continue;

    // 在段落内按句末标点分割
    const rawSentences: string[] = [];
    let current = "";

    for (let i = 0; i < para.length; i++) {
      current += para[i];

      if (SENTENCE_ENDINGS.test(para[i])) {
        // 吞掉紧跟的引号/括号
        while (i + 1 < para.length && TRAILING_QUOTES.test(para[i + 1])) {
          i++;
          current += para[i];
        }
        const trimmed = current.trim();
        if (trimmed.length > 0) {
          rawSentences.push(trimmed);
        }
        current = "";
      }
    }

    // 剩余文本作为最后一个句子
    if (current.trim().length > 0) {
      rawSentences.push(current.trim());
    }

    // 过滤过短句子并记录位置信息
    for (let si = 0; si < rawSentences.length; si++) {
      const s = rawSentences[si];
      if (s.length < minLength) continue;

      sentences.push({
        index: globalIndex++,
        text: s,
        paragraphIndex: pi,
        sentenceInParagraph: si,
        isParagraphStart: si === 0,
        isParagraphEnd: si === rawSentences.length - 1,
        isFirstParagraph: pi === 0,
        score: 0,
      });
    }
  }

  return sentences;
}

// ============================================================
// 2. 字级 n-gram 提取
// ============================================================

/**
 * 从文本中提取字级 n-gram 集合
 *
 * 优势：不需要分词器，直接按字符滑动窗口
 * 示例："今天天气好" 的 bigram → {"今天", "天天", "天气", "气好"}
 */
function extractNgrams(text: string, n: number): Set<string> {
  const ngrams = new Set<string>();
  if (!text || text.length === 0) return ngrams;

  // 去除标点和空白，保留中文、字母、数字
  const cleaned = text.replace(/[^\u4e00-\u9fff\u3400-\u4dbf\u3007a-zA-Z0-9]/g, "");
  if (cleaned.length < n) return ngrams;

  for (let i = 0; i <= cleaned.length - n; i++) {
    ngrams.add(cleaned.substring(i, i + n));
  }
  return ngrams;
}

// ============================================================
// 2b. TF-IDF 关键词提取（方案二）
// ============================================================

/** 中文停用字（高频但无实际意义的字） */
const STOP_CHARS = new Set("的了是在我有和就不人都一这中大为上个国也子时道说出会要没成好能对然她过生里后以到去能得着年这".split(""));

/**
 * 从全文中提取关键词（字级 unigram 频率 + TF-IDF 简化版）
 *
 * 简化思路：
 * - 以句子为"文档"，统计每个字在多少个句子中出现（DF）
 * - TF = 该字在全文中出现的次数
 * - IDF = log(总句数 / (DF + 1))
 * - TF-IDF = TF * IDF
 * - 取 Top-K 作为关键词
 *
 * 返回关键词集合
 */
function extractKeywords(
  sentences: SentenceInfo[],
  topK: number
): Set<string> {
  if (sentences.length === 0) return new Set();

  // 统计全文 TF 和句子级 DF
  const tf = new Map<string, number>();
  const df = new Map<string, number>();

  for (const sent of sentences) {
    const cleaned = sent.text.replace(/[^\u4e00-\u9fff\u3400-\u4dbf]/g, "");
    const seen = new Set<string>();

    for (const ch of cleaned) {
      if (STOP_CHARS.has(ch)) continue;
      tf.set(ch, (tf.get(ch) || 0) + 1);
      if (!seen.has(ch)) {
        df.set(ch, (df.get(ch) || 0) + 1);
        seen.add(ch);
      }
    }
  }

  // 计算 TF-IDF
  const n = sentences.length;
  const tfidf = new Map<string, number>();

  for (const [ch, freq] of tf) {
    const docFreq = df.get(ch) || 1;
    // IDF: 在越少句子中出现的字越有区分度
    const idf = Math.log((n + 1) / (docFreq + 1)) + 1;
    tfidf.set(ch, freq * idf);
  }

  // 取 Top-K
  const sorted = [...tfidf.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, topK);

  return new Set(sorted.map(([ch]) => ch));
}

/**
 * 计算句子的关键词命中权重
 *
 * 句子中包含的关键词越多，权重越高
 * weight = keywordWeight ^ (命中关键词数 / 关键词总数)
 */
function keywordWeightForSentence(
  sentence: SentenceInfo,
  keywords: Set<string>,
  keywordWeight: number
): number {
  if (keywords.size === 0 || keywordWeight === 0) return 1.0;

  const cleaned = sentence.text.replace(/[^\u4e00-\u9fff\u3400-\u4dbf]/g, "");
  let hits = 0;
  for (const ch of cleaned) {
    if (keywords.has(ch)) hits++;
  }

  if (hits === 0) return 1.0;

  // 使用对数平滑，避免命中数过多时权重爆炸
  const ratio = hits / keywords.size;
  return Math.pow(keywordWeight, Math.min(ratio, 1.0));
}

// ============================================================
// 3. 句子相似度计算
// ============================================================

/**
 * 计算两个句子的 n-gram 相似度
 *
 * 公式：sim(i,j) = |ngrams(i) ∩ ngrams(j)| / (log(|ngrams(i)|) + log(|ngrams(j)|))
 *
 * 使用 log 是为了防止长句子因 n-gram 数量多而获得不公平的优势
 */
function similarity(ngramsA: Set<string>, ngramsB: Set<string>): number {
  if (ngramsA.size === 0 || ngramsB.size === 0) return 0;

  let intersection = 0;
  for (const gram of ngramsA) {
    if (ngramsB.has(gram)) intersection++;
  }

  if (intersection === 0) return 0;

  const denom = Math.log(ngramsA.size + 1) + Math.log(ngramsB.size + 1);
  if (denom === 0) return 0;

  return safeNumber(intersection / denom);
}

// ============================================================
// 4. 位置权重计算
// ============================================================

/**
 * 根据句子位置计算先验权重
 *
 * 规则（可叠加）：
 * - 首段首句：weightFirstSentence
 * - 首段其他句：weightFirstParagraph
 * - 段落首句：weightParagraphStart
 * - 段落末句：weightParagraphEnd
 * - 其他：1.0
 */
function positionWeight(
  sentence: SentenceInfo,
  opts: Required<SummaryOptions>
): number {
  let weight = 1.0;

  if (sentence.isFirstParagraph && sentence.isParagraphStart) {
    weight *= opts.weightFirstSentence;
  } else if (sentence.isFirstParagraph) {
    weight *= opts.weightFirstParagraph;
  }

  if (!sentence.isFirstParagraph && sentence.isParagraphStart) {
    weight *= opts.weightParagraphStart;
  }

  if (sentence.isParagraphEnd) {
    weight *= opts.weightParagraphEnd;
  }

  return safeNumber(weight, 1.0);
}

// ============================================================
// 5. TextRank 算法
// ============================================================

/**
 * TextRank 迭代计算
 *
 * 公式：WS(Vi) = (1-d) * init(Vi) + d * Σ(sim(Vi,Vj) / Σsim(Vj,Vk)) * WS(Vj)
 *
 * 其中 init(Vi) = 位置先验权重 × 关键词权重，d 为阻尼系数
 */
function textRank(
  sentences: SentenceInfo[],
  ngramSets: Set<string>[],
  opts: Required<SummaryOptions>,
  keywords?: Set<string>
): void {
  const n = sentences.length;
  if (n === 0) return;
  if (n === 1) {
    let score = positionWeight(sentences[0], opts);
    if (keywords && opts.keywordWeight > 0) {
      score *= keywordWeightForSentence(sentences[0], keywords, opts.keywordWeight);
    }
    sentences[0].score = safeNumber(score, 1.0);
    return;
  }

  // 构建相似度矩阵
  const simMatrix: number[][] = Array.from({ length: n }, () => new Array(n).fill(0));
  const simSums: number[] = new Array(n).fill(0);

  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      const sim = similarity(ngramSets[i], ngramSets[j]);
      simMatrix[i][j] = sim;
      simMatrix[j][i] = sim;
      simSums[i] += sim;
      simSums[j] += sim;
    }
  }

  // 初始化分数 = 位置先验权重 × 关键词权重
  const initScores = sentences.map((s) => {
    let score = positionWeight(s, opts);
    if (keywords && opts.keywordWeight > 0) {
      score *= keywordWeightForSentence(s, keywords, opts.keywordWeight);
    }
    return safeNumber(score, 1.0);
  });
  const scores = [...initScores];

  // 迭代
  for (let iter = 0; iter < opts.maxIterations; iter++) {
    const newScores = new Array(n).fill(0);
    let maxDiff = 0;

    for (let i = 0; i < n; i++) {
      let rankSum = 0;
      for (let j = 0; j < n; j++) {
        if (i === j || simSums[j] === 0) continue;
        rankSum += (simMatrix[i][j] / simSums[j]) * scores[j];
      }

      newScores[i] = (1 - opts.dampingFactor) * initScores[i] + opts.dampingFactor * rankSum;
      // 数值安全
      newScores[i] = safeNumber(newScores[i], initScores[i]);

      const diff = Math.abs(newScores[i] - scores[i]);
      if (diff > maxDiff) maxDiff = diff;
    }

    // 更新分数
    for (let i = 0; i < n; i++) {
      scores[i] = newScores[i];
    }

    // 收敛判断
    if (maxDiff < opts.convergenceThreshold) break;
  }

  // 写回得分
  for (let i = 0; i < n; i++) {
    sentences[i].score = safeNumber(scores[i], initScores[i]);
  }
}

// ============================================================
// 6. 压缩级别 → 句子数量映射
// ============================================================

/**
 * 根据压缩级别计算应提取的句子数量
 *
 * 级别 5: 100% 句子
 * 级别 4: ~50% 句子
 * 级别 3: ~30% 句子（最少 3 句）
 * 级别 2: ~20% 句子（最少 2 句）
 * 级别 1: 1 句（后续走子句逻辑）
 */
function sentenceCountForLevel(
  totalSentences: number,
  level: CompressionLevel
): number {
  if (level === 5) return totalSentences;
  if (level === 4) return Math.max(3, Math.ceil(totalSentences * 0.5));
  if (level === 3) return Math.max(3, Math.ceil(totalSentences * 0.3));
  if (level === 2) return Math.max(2, Math.ceil(totalSentences * 0.2));
  return 1; // level 1
}

// ============================================================
// 6b. MMR 多样性选句（方案一）
// ============================================================

/**
 * 使用 MMR（Maximal Marginal Relevance）策略选句
 *
 * 每次选择句子时，综合考虑：
 * - 相关性：TextRank 得分高
 * - 多样性：与已选句子不重复
 *
 * 公式：MMR(s) = λ * score(s) - (1-λ) * max_sim(s, 已选句子集)
 *
 * λ=1.0 退化为纯得分排序，λ=0.5 最大多样性
 */
function selectByMMR(
  sentences: SentenceInfo[],
  ngramSets: Set<string>[],
  targetCount: number,
  lambda: number
): SentenceInfo[] {
  if (sentences.length <= targetCount) return [...sentences];

  // 归一化得分到 [0, 1]
  const scores = sentences.map((s) => s.score);
  const maxScore = Math.max(...scores);
  const minScore = Math.min(...scores);
  const scoreRange = maxScore - minScore || 1;

  const normalizedScores = scores.map((s) => (s - minScore) / scoreRange);

  // 已选句子索引集合
  const selected: number[] = [];
  const remaining = new Set(sentences.map((_, i) => i));

  // 第一句：选得分最高的
  let bestIdx = -1;
  let bestScore = -Infinity;
  for (let i = 0; i < sentences.length; i++) {
    if (normalizedScores[i] > bestScore) {
      bestScore = normalizedScores[i];
      bestIdx = i;
    }
  }
  selected.push(bestIdx);
  remaining.delete(bestIdx);

  // 后续句子：用 MMR 选择
  while (selected.length < targetCount && remaining.size > 0) {
    let bestMMR = -Infinity;
    let bestCandidate = -1;

    for (const idx of remaining) {
      // 相关性项
      const relevance = lambda * normalizedScores[idx];

      // 多样性惩罚项：与已选句子的最大相似度
      let maxSim = 0;
      for (const selIdx of selected) {
        const sim = similarity(ngramSets[idx], ngramSets[selIdx]);
        if (sim > maxSim) maxSim = sim;
      }
      const diversity = (1 - lambda) * maxSim;

      const mmr = relevance - diversity;
      if (mmr > bestMMR) {
        bestMMR = mmr;
        bestCandidate = idx;
      }
    }

    if (bestCandidate === -1) break;
    selected.push(bestCandidate);
    remaining.delete(bestCandidate);
  }

  return selected.map((idx) => sentences[idx]);
}

// ============================================================
// 7. 子句分割（compressionLevel=1 专用）
// ============================================================

/** 中文子句分隔标点 */
const CLAUSE_SEPARATORS = /[，、,；;：:]/;

/**
 * 将句子拆分为子句
 *
 * 规则：
 * - 按逗号、顿号、分号、冒号分割
 * - 保留分隔符在前一个子句末尾（保持可读性）
 * - 过滤过短的子句
 */
function splitClauses(
  sentence: string,
  minLength: number
): string[] {
  if (!sentence || sentence.length === 0) return [];

  const clauses: string[] = [];
  let current = "";

  for (let i = 0; i < sentence.length; i++) {
    current += sentence[i];

    if (CLAUSE_SEPARATORS.test(sentence[i])) {
      const trimmed = current.trim();
      if (trimmed.length >= minLength) {
        clauses.push(trimmed);
      }
      current = "";
    }
  }

  // 剩余文本
  const remaining = current.trim();
  if (remaining.length >= minLength) {
    clauses.push(remaining);
  }

  return clauses;
}

// ============================================================
// 8. 子句级 TextRank（compressionLevel=1 专用）
// ============================================================

/** 主干子句加权系数 */
const MAIN_CLAUSE_BOOST = 1.3;

/**
 * 对子句列表运行 TextRank
 *
 * 与句子级 TextRank 类似，但：
 * - 主干子句（每句第一个子句）获得额外先验权重
 * - 初始分数来自源句子得分
 * - 使用 n-gram 相似度
 */
function clauseTextRank(
  clauses: ClauseInfo[],
  ngramSets: Set<string>[],
  opts: Required<SummaryOptions>
): void {
  const n = clauses.length;
  if (n === 0) return;
  if (n === 1) {
    clauses[0].score = safeNumber(clauses[0].score, 1.0);
    return;
  }

  // 构建相似度矩阵
  const simMatrix: number[][] = Array.from({ length: n }, () => new Array(n).fill(0));
  const simSums: number[] = new Array(n).fill(0);

  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      const sim = similarity(ngramSets[i], ngramSets[j]);
      simMatrix[i][j] = sim;
      simMatrix[j][i] = sim;
      simSums[i] += sim;
      simSums[j] += sim;
    }
  }

  // 初始分数：来自源句子的得分作为先验，主干子句加权
  const initScores = clauses.map((c) => {
    const base = c.score || 1.0;
    return c.isMainClause ? base * MAIN_CLAUSE_BOOST : base;
  });
  const scores = [...initScores];

  // 迭代
  for (let iter = 0; iter < opts.maxIterations; iter++) {
    const newScores = new Array(n).fill(0);
    let maxDiff = 0;

    for (let i = 0; i < n; i++) {
      let rankSum = 0;
      for (let j = 0; j < n; j++) {
        if (i === j || simSums[j] === 0) continue;
        rankSum += (simMatrix[i][j] / simSums[j]) * scores[j];
      }

      newScores[i] = (1 - opts.dampingFactor) * initScores[i] + opts.dampingFactor * rankSum;
      newScores[i] = safeNumber(newScores[i], initScores[i]);

      const diff = Math.abs(newScores[i] - scores[i]);
      if (diff > maxDiff) maxDiff = diff;
    }

    for (let i = 0; i < n; i++) {
      scores[i] = newScores[i];
    }

    if (maxDiff < opts.convergenceThreshold) break;
  }

  for (let i = 0; i < n; i++) {
    clauses[i].score = safeNumber(scores[i], initScores[i]);
  }
}

// ============================================================
// 9. 多轮重排（compressionLevel=2 专用）
// ============================================================

/**
 * 多轮 TextRank 重排
 *
 * 第一轮提取 Top-N 句子，将这些句子视为新文档，
 * 重新计算 n-gram 相似度和 TextRank，再取 Top-M 句子。
 * 这样在精选句子间重新排序，能更精准地找到核心句。
 */
function rerankSentences(
  sentences: SentenceInfo[],
  targetCount: number,
  opts: Required<SummaryOptions>,
  keywords?: Set<string>
): SentenceInfo[] {
  // 第一轮：在全部句子上运行 TextRank
  const ngramSets = sentences.map((s) => extractNgrams(s.text, opts.ngramSize));
  textRank(sentences, ngramSets, opts, keywords);

  // 取 Top-N（N 为 targetCount 的 2 倍，至少 5 句）
  const firstPassCount = Math.max(5, targetCount * 2);
  const firstPass = [...sentences]
    .sort((a, b) => b.score - a.score)
    .slice(0, Math.min(firstPassCount, sentences.length));

  // 如果句子太少，不需要第二轮
  if (firstPass.length <= targetCount) {
    return firstPass;
  }

  // 第二轮：在精选句子上重新运行 TextRank
  const secondPassSentences: SentenceInfo[] = firstPass.map((s, i) => ({
    ...s,
    index: i,
  }));

  const secondNgramSets = secondPassSentences.map((s) =>
    extractNgrams(s.text, opts.ngramSize)
  );
  textRank(secondPassSentences, secondNgramSets, opts);

  // 按第二轮得分排序，取 Top-M
  const result = [...secondPassSentences]
    .sort((a, b) => b.score - a.score)
    .slice(0, targetCount);

  // 恢复原始 index
  return result.map((s) => {
    const original = firstPass.find((f) => f.text === s.text);
    return original || s;
  });
}

// ============================================================
// 10. 极致压缩：子句级提取（compressionLevel=1 专用）
// ============================================================

/** 句末标点，用于判断子句是否已自带句末标点 */
const SENTENCE_FINAL_PUNCT = /[。！？；!?;]$/;

/**
 * 智能拼接子句，处理标点去重
 *
 * 规则：
 * - 子句末尾如果已有逗号/分号等子句分隔符，不再追加逗号
 * - 子句末尾如果是句末标点（。！？；），用空格连接
 * - 否则用逗号连接
 */
function joinClauses(clauses: string[]): string {
  if (clauses.length === 0) return "";
  if (clauses.length === 1) return clauses[0];

  let result = clauses[0];

  for (let i = 1; i < clauses.length; i++) {
    const prev = result;
    const curr = clauses[i];
    const lastChar = prev[prev.length - 1];

    // 前一个子句以句末标点结尾 -> 空格连接
    if (SENTENCE_FINAL_PUNCT.test(prev)) {
      result = result + " " + curr;
    }
    // 前一个子句以子句分隔符（逗号等）结尾 -> 直接连接，不再加逗号
    else if (CLAUSE_SEPARATORS.test(lastChar)) {
      result = result + curr;
    }
    // 正常情况 -> 用逗号连接
    else {
      result = result + "，" + curr;
    }
  }

  return result;
}

// ============================================================
// 10b. 子句连词处理（方案三）
// ============================================================

/**
 * 中文连词/转折词表
 *
 * 这些词在子句开头时，脱离上下文会导致语义不完整
 * 例如："也标志着..." → 读者不知道"也"指代什么
 */
const CLAUSE_CONJUNCTIONS = [
  // 转折
  "但", "但是", "然而", "不过", "可是", "却", "反而", "只是",
  // 递进/并列
  "也", "而且", "并且", "此外", "另外", "同时", "既", "又",
  // 因果
  "因此", "所以", "于是", "从而", "进而", "故",
  // 让步
  "虽然", "尽管", "固然", "即使", "就算",
  // 条件
  "如果", "假如", "只要", "只有", "除非",
  // 总结
  "总之", "综上", "由此可见", "总的来说",
];

/** 连词最大长度（用于匹配） */
const MAX_CONJ_LEN = Math.max(...CLAUSE_CONJUNCTIONS.map((c) => c.length));

/**
 * 处理子句开头的连词
 *
 * 策略：
 * 1. 如果子句以连词开头，尝试向前合并同句的前一个子句（如果前一个子句也被选中）
 * 2. 如果无法合并，则剥离连词
 *
 * @param orderedClauses 已按原文顺序排列的子句列表
 * @param allClauses 所有子句（用于查找前一个子句）
 * @returns 处理后的子句文本数组
 */
function processConjunctions(
  orderedClauses: ClauseInfo[],
  allClauses: ClauseInfo[]
): string[] {
  // 建立快速查找：sourceSentenceIndex + clauseIndex -> ClauseInfo
  const clauseMap = new Map<string, ClauseInfo>();
  for (const c of allClauses) {
    clauseMap.set(c.sourceSentenceIndex + ":" + c.clauseIndex, c);
  }

  // 建立选中子句集合
  const selectedSet = new Set(orderedClauses.map((c) => c.sourceSentenceIndex + ":" + c.clauseIndex));

  const results: string[] = [];

  for (const clause of orderedClauses) {
    let text = clause.text;

    // 检测子句开头是否为连词
    const matchedConj = matchConjunction(text);

    if (matchedConj) {
      // 尝试向前合并：查找同句的前一个子句
      const prevKey = clause.sourceSentenceIndex + ":" + (clause.clauseIndex - 1);
      const prevClause = clauseMap.get(prevKey);

      if (prevClause && selectedSet.has(prevKey)) {
        // 前一个子句也被选中，不需要处理（它们会自然拼接）
        // 但需要确保连词不会导致拼接后语义怪异
        // 这里不做额外处理，让 joinClauses 处理拼接
      } else {
        // 前一个子句未被选中，剥离连词
        text = text.substring(matchedConj.length);
        // 清理连词后的前导标点（如 "然而，" → 剥离 "然而" 后剩 "，数据..."）
        text = text.replace(/^[，、,；;：:\s]+/, "");
      }
    }

    if (text.length > 0) {
      results.push(text);
    }
  }

  return results;
}

/**
 * 匹配文本开头的连词
 *
 * 从长到短匹配，避免 "但是" 被误匹配为 "但"
 * 返回匹配到的连词，未匹配返回 null
 */
function matchConjunction(text: string): string | null {
  for (let len = MAX_CONJ_LEN; len >= 1; len--) {
    if (len > text.length) continue;
    const prefix = text.substring(0, len);
    if (CLAUSE_CONJUNCTIONS.includes(prefix)) {
      return prefix;
    }
  }
  return null;
}

/**
 * 极致压缩：先句子级提取 Top-N，再拆子句，子句级 TextRank，拼接 Top 子句
 *
 * 流程：
 * 1. 句子级 TextRank，取 Top-5 句
 * 2. 将这 5 句拆分为子句，标记主干子句
 * 3. 子句级 TextRank（以源句子得分为先验，主干子句加权）
 * 4. 取 Top-K 子句，按原文顺序排列
 * 5. 连词处理：剥离或合并脱离上下文的连词
 * 6. 拼接为一句话（智能标点处理）
 */
function extractClauseSummary(
  sentences: SentenceInfo[],
  opts: Required<SummaryOptions>,
  keywords?: Set<string>
): { summary: string[]; clauses: ClauseInfo[] } {
  // Step 1: 句子级 TextRank，取 Top-5
  const ngramSets = sentences.map((s) => extractNgrams(s.text, opts.ngramSize));
  textRank(sentences, ngramSets, opts, keywords);

  const topSentenceCount = Math.min(5, sentences.length);
  const topSentences = [...sentences]
    .sort((a, b) => b.score - a.score)
    .slice(0, topSentenceCount);

  // Step 2: 拆分子句，标记主干子句
  const allClauses: ClauseInfo[] = [];
  for (const sent of topSentences) {
    const rawClauses = splitClauses(sent.text, opts.minClauseLength);
    for (let ci = 0; ci < rawClauses.length; ci++) {
      allClauses.push({
        text: rawClauses[ci],
        sourceSentenceIndex: sent.index,
        clauseIndex: ci,
        isMainClause: ci === 0, // 第一个子句是主干子句
        score: sent.score,
      });
    }
  }

  if (allClauses.length === 0) {
    // 子句拆分失败，退回到取得分最高的 1 句
    const best = topSentences[0];
    return {
      summary: [best.text],
      clauses: [{
        text: best.text,
        sourceSentenceIndex: best.index,
        clauseIndex: 0,
        isMainClause: true,
        score: best.score,
      }],
    };
  }

  // Step 3: 子句级 TextRank
  const clauseNgramSets = allClauses.map((c) =>
    extractNgrams(c.text, opts.ngramSize)
  );
  clauseTextRank(allClauses, clauseNgramSets, opts);

  // Step 4: 取 Top-K 子句
  const maxClauses = Math.min(opts.maxClauses, allClauses.length);
  const topClauses = [...allClauses]
    .sort((a, b) => b.score - a.score)
    .slice(0, maxClauses);

  // Step 5: 按源句子在原文中的顺序排列子句（保持可读性）
  const orderedClauses = [...topClauses].sort((a, b) => {
    if (a.sourceSentenceIndex !== b.sourceSentenceIndex) {
      return a.sourceSentenceIndex - b.sourceSentenceIndex;
    }
    return a.clauseIndex - b.clauseIndex;
  });

  // Step 6: 连词处理（剥离脱离上下文的连词）
  const processedTexts = processConjunctions(orderedClauses, allClauses);

  // Step 7: 拼接为一句话（智能标点处理）
  const summaryText = joinClauses(processedTexts);

  return {
    summary: [summaryText],
    clauses: allClauses,
  };
}

// ============================================================
// 11. 主接口
// ============================================================

/**
 * 提取中文文本概要
 *
 * @param text 原始中文文本
 * @param options 配置选项
 * @returns 概要提取结果
 *
 * @example
 * ```ts
 * import { extractSummary } from 'chinese-summary';
 *
 * // 使用 sentenceCount（兼容旧接口）
 * const result1 = extractSummary(text, { sentenceCount: 2 });
 *
 * // 使用 compressionLevel（推荐）
 * const result2 = extractSummary(text, { compressionLevel: 1 }); // 极致压缩
 * const result3 = extractSummary(text, { compressionLevel: 3 }); // 中度压缩
 * ```
 */
export function extractSummary(
  text: string,
  options: SummaryOptions = {}
): SummaryResult {
  // ─── 输入校验 ───
  if (text === null || text === undefined) {
    return { summary: [], sentences: [], text: "", compressionLevel: 3 };
  }
  if (typeof text !== "string") {
    try {
      text = String(text);
    } catch {
      return { summary: [], sentences: [], text: "", compressionLevel: 3 };
    }
  }
  // 去除 BOM 和零宽字符
  text = text.replace(/[\uFEFF\u200B\u200C\u200D\u00AD]/g, "");
  // 统一换行符
  text = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n");

  if (text.trim().length === 0) {
    return { summary: [], sentences: [], text: "", compressionLevel: 3 };
  }

  // ─── 参数校验 ───
  const opts = sanitizeOptions(options);
  const level = opts.compressionLevel;

  // Step 1: 句子分割
  const sentences = splitSentences(text, opts.minSentenceLength);

  if (sentences.length === 0) {
    return { summary: [], sentences: [], text: "", compressionLevel: level };
  }

  // Step 1b: 提取全文关键词（方案二：TF-IDF 关键词加权）
  const keywords = opts.keywordWeight > 0
    ? extractKeywords(sentences, Math.min(20, Math.max(5, Math.ceil(sentences.length * 0.5))))
    : undefined;

  // ─── 级别 5：不压缩 ───
  if (level === 5) {
    // 仍然计算得分（用于调试）
    const ngramSets = sentences.map((s) => extractNgrams(s.text, opts.ngramSize));
    textRank(sentences, ngramSets, opts, keywords);

    const summary = sentences.map((s) => s.text);
    return { summary, sentences, text: summary.join(" "), compressionLevel: level };
  }

  // ─── 级别 1：极致压缩（子句级） ───
  if (level === 1) {
    if (sentences.length <= 1) {
      const summary = sentences.map((s) => s.text);
      return { summary, sentences, text: summary.join(" "), compressionLevel: level };
    }

    const { summary, clauses } = extractClauseSummary(sentences, opts, keywords);
    return { summary, sentences, text: summary.join(" "), compressionLevel: level, clauses };
  }

  // ─── 级别 2/3/4：句子级提取 ───
  let targetCount: number;

  if (options.sentenceCount !== undefined && options.compressionLevel === undefined) {
    // 旧接口：用户指定了 sentenceCount 但未指定 compressionLevel
    targetCount = opts.sentenceCount;
  } else {
    targetCount = sentenceCountForLevel(sentences.length, level);
  }

  // 如果句子数少于目标数，全部返回
  if (sentences.length <= targetCount) {
    const summary = sentences.map((s) => s.text);
    return { summary, sentences, text: summary.join(" "), compressionLevel: level };
  }

  // ─── 级别 2：多轮重排 + MMR ───
  if (level === 2) {
    const topSentences = rerankSentences(sentences, targetCount, opts, keywords);

    const selectedIndices = new Set(topSentences.map((s) => s.index));
    const summary = sentences
      .filter((s) => selectedIndices.has(s.index))
      .map((s) => s.text);

    // 也给所有句子打分（用于调试）
    const ngramSets = sentences.map((s) => extractNgrams(s.text, opts.ngramSize));
    textRank(sentences, ngramSets, opts, keywords);

    return { summary, sentences, text: summary.join(" "), compressionLevel: level };
  }

  // ─── 级别 3/4：TextRank + 关键词加权 + MMR 选句 ───
  const ngramSets = sentences.map((s) => extractNgrams(s.text, opts.ngramSize));
  textRank(sentences, ngramSets, opts, keywords);

  // 使用 MMR 选句（mmrLambda=1.0 时退化为纯得分排序）
  const topN = selectByMMR(sentences, ngramSets, targetCount, opts.mmrLambda);

  const selectedIndices = new Set(topN.map((s) => s.index));
  const summary = sentences
    .filter((s) => selectedIndices.has(s.index))
    .map((s) => s.text);

  return { summary, sentences, text: summary.join(" "), compressionLevel: level };
}

/**
 * 仅获取句子得分（不提取摘要），用于调试和分析
 */
export function rankSentences(
  text: string,
  options: SummaryOptions = {}
): SentenceInfo[] {
  // 输入校验
  if (text === null || text === undefined || typeof text !== "string") {
    return [];
  }
  if (text.trim().length === 0) return [];

  const opts = sanitizeOptions(options);
  const sentences = splitSentences(text, opts.minSentenceLength);
  if (sentences.length === 0) return [];

  const keywords = opts.keywordWeight > 0
    ? extractKeywords(sentences, Math.min(20, Math.max(5, Math.ceil(sentences.length * 0.5))))
    : undefined;

  const ngramSets = sentences.map((s) => extractNgrams(s.text, opts.ngramSize));
  textRank(sentences, ngramSets, opts, keywords);

  return [...sentences].sort((a, b) => b.score - a.score);
}
