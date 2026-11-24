[English](./usage-guide-en.md)

# chinese-summary 使用指南

中文文本概要提取库 — 详细使用文档

> Copyright (c) 2025 北京锋通科技有限公司
> Authors: 郭玉峰, 吴琼
> License: MIT

## 特性

- **零外部依赖**：纯 TypeScript 实现，无需分词器、无需 AI 模型
- **字级 n-gram**：绕过中文分词，直接按字符滑动窗口计算相似度
- **5 级压缩**：从"不压缩"到"极致压缩为一句话"，灵活控制摘要长度
- **位置加权**：首段首句、段落首尾句获得更高先验权重
- **TF-IDF 关键词加权**：包含全文关键词的句子获得额外权重，摘要更切题
- **MMR 去冗余**：选句时兼顾相关性和多样性，避免语义重复
- **子句连词处理**：极致压缩时自动剥离脱离上下文的连词，保证可读性
- **健壮性**：完善的输入校验、参数校验、数值安全防护

## 安装

```bash
npm install chinese-summary
```

或直接引用源码：

```ts
import { extractSummary, rankSentences } from "./src/chinese-summary";
```

## 构建

项目提供四种编译产物，覆盖所有使用场景：

| 文件 | 格式 | 适用环境 |
|------|------|----------|
| `dist/chinese-summary.cjs` | CJS | Node.js `require()` |
| `dist/chinese-summary.mjs` | ESM | Node.js `import`、浏览器 `<script type="module">` |
| `dist/chinese-summary.iife.js` | IIFE | 浏览器 `<script>` 标签，全局变量 `ChineseSummary` |
| `dist/chinese-summary.d.ts` | 类型声明 | TypeScript 智能提示 |

```bash
# 构建
npm run build
```

## 使用方式

### Node.js（CJS）

```js
const { extractSummary, rankSentences } = require("chinese-summary");

const text = "人工智能是计算机科学的重要分支。深度学习推动了AI的快速发展。自然语言处理取得了突破性进展。";

const result = extractSummary(text, { compressionLevel: 3 });
console.log(result.text);
```

### Node.js（ESM）

```ts
import { extractSummary, rankSentences } from "chinese-summary";

const text = "人工智能是计算机科学的重要分支。深度学习推动了AI的快速发展。自然语言处理取得了突破性进展。";

const result = extractSummary(text, { compressionLevel: 3 });
console.log(result.text);
```

### 浏览器（IIFE — `<script>` 标签）

```html
<script src="dist/chinese-summary.iife.js"></script>
<script>
  var text = "人工智能是计算机科学的重要分支。深度学习推动了AI的快速发展。";
  var result = ChineseSummary.extractSummary(text, { compressionLevel: 2 });
  console.log(result.text);
</script>
```

> IIFE 版本通过全局变量 `ChineseSummary` 暴露 `extractSummary` 和 `rankSentences` 两个函数。

### 浏览器（ES Module）

```html
<script type="module">
  import { extractSummary } from "./dist/chinese-summary.mjs";

  const text = document.querySelector("article").textContent;
  const result = extractSummary(text, { compressionLevel: 2 });
  console.log(result.text);
</script>
```

### npm + 打包工具（Webpack / Vite / Rollup）

```ts
import { extractSummary } from "chinese-summary";

const result = extractSummary(text, { compressionLevel: 2 });
```

## 快速开始

```ts
import { extractSummary } from "chinese-summary";

const text = "人工智能是计算机科学的重要分支，它致力于研究和开发用于模拟人类智能的理论和方法。深度学习技术的出现是这一轮AI复兴的关键推动力。自然语言处理是人工智能最活跃的研究方向之一。然而，人工智能的快速发展也带来了一系列社会问题和伦理挑战。展望未来，人工智能将继续深刻改变人类社会的方方面面。";

// 默认：级别 3（中度压缩，约 30% 句子）
const result = extractSummary(text);
console.log(result.text);
// → "人工智能是计算机科学的重要分支，它致力于研究和开发用于模拟人类智能的理论和方法。 自然语言处理是人工智能最活跃的研究方向之一。"

// 极致压缩：压缩为一句话
const extreme = extractSummary(text, { compressionLevel: 1 });
console.log(extreme.text);
// → "人工智能是计算机科学的重要分支，自然语言处理取得了突破性进展"

// 指定句子数量（兼容旧接口）
const legacy = extractSummary(text, { sentenceCount: 2 });
console.log(legacy.text);
```

## 压缩级别

| 级别 | 说明 | 压缩策略 | 适用场景 |
|------|------|----------|----------|
| 1 | 极致压缩 | 子句级提取，拼接为一句话 | 标题生成、推送摘要 |
| 2 | 高度压缩 | 约 20% 句子 + 多轮重排 | 短摘要、列表预览 |
| 3 | 中度压缩 | 约 30% 句子（**默认**） | 通用摘要 |
| 4 | 轻度压缩 | 约 50% 句子 | 长摘要、速读 |
| 5 | 不压缩 | 返回全部句子 | 仅排序、调试 |

各级别对比示例（1584 字 AI 文章）：

| 级别 | 字数 | 压缩率 |
|------|------|--------|
| 1 | 69 字 | 95.6% |
| 2 | 408 字 | 74.2% |
| 3 | 536 字 | 66.2% |
| 4 | 886 字 | 44.1% |
| 5 | 1603 字 | -1.2% |

## API

### `extractSummary(text, options?)`

提取中文文本概要。

**参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `text` | `string` | 是 | 原始中文文本 |
| `options` | `SummaryOptions` | 否 | 配置选项 |

**返回值：** `SummaryResult`

```ts
interface SummaryResult {
  summary: string[];          // 摘要句子（按原文顺序）
  sentences: SentenceInfo[];  // 所有句子及其得分
  text: string;               // 摘要文本（句子间用空格连接）
  compressionLevel: 1|2|3|4|5;
  clauses?: ClauseInfo[];     // 子句信息（仅级别 1）
}
```

```ts
interface ClauseInfo {
  text: string;               // 子句文本
  sourceSentenceIndex: number;// 来源句子序号
  clauseIndex: number;        // 在来源句子中的序号
  isMainClause: boolean;      // 是否为句子的主干子句（第一个子句）
  score: number;              // TextRank 得分
}
```

### `rankSentences(text, options?)`

仅获取句子得分排名，不提取摘要。用于调试和分析。

**返回值：** `SentenceInfo[]`（按得分降序排列）

```ts
interface SentenceInfo {
  index: number;              // 全文序号
  text: string;               // 句子文本
  paragraphIndex: number;     // 段落序号
  sentenceInParagraph: number;// 段落内序号
  isParagraphStart: boolean;  // 是否段落首句
  isParagraphEnd: boolean;    // 是否段落末句
  isFirstParagraph: boolean;  // 是否首段
  score: number;              // TextRank 得分
}
```

## 配置选项

### 压缩控制

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `compressionLevel` | `1\|2\|3\|4\|5` | `3` | 压缩级别，与 `sentenceCount` 互斥，优先级更高 |
| `sentenceCount` | `number` | `3` | 摘要句子数量（旧接口，仅未指定 `compressionLevel` 时生效） |
| `maxClauses` | `number` | `3` | 极致压缩时最大子句数（仅级别 1） |

### TextRank 算法

| 选项 | 类型 | 默认值 | 范围 | 说明 |
|------|------|--------|------|------|
| `ngramSize` | `number` | `2` | 1-5 | n-gram 大小，2=bigram |
| `dampingFactor` | `number` | `0.85` | 0.1-0.95 | 阻尼系数 d |
| `maxIterations` | `number` | `30` | 1-200 | 最大迭代次数 |
| `convergenceThreshold` | `number` | `0.0001` | 1e-8~1 | 收敛阈值 |

### 位置权重

| 选项 | 类型 | 默认值 | 范围 | 说明 |
|------|------|--------|------|------|
| `weightFirstSentence` | `number` | `1.5` | 0.5-5 | 首段首句权重 |
| `weightFirstParagraph` | `number` | `1.2` | 0.5-5 | 首段其他句权重 |
| `weightParagraphStart` | `number` | `1.1` | 0.5-5 | 段落首句权重 |
| `weightParagraphEnd` | `number` | `1.05` | 0.5-5 | 段落末句权重 |

权重可叠加。例如首段首句 = `weightFirstSentence`，首段其他句 = `weightFirstParagraph`，非首段段落首句 = `weightParagraphStart`，段落末句额外乘以 `weightParagraphEnd`。

### 多样性与关键词

| 选项 | 类型 | 默认值 | 范围 | 说明 |
|------|------|--------|------|------|
| `mmrLambda` | `number` | `0.7` | 0.3-1.0 | MMR 多样性系数 λ（仅级别 2-4） |
| `keywordWeight` | `number` | `1.2` | 0-5 | 关键词权重系数，0=关闭 |

**mmrLambda 调参指南：**
- `1.0`：纯得分排序，关闭 MMR（等同旧版行为）
- `0.7`：默认，平衡相关性与多样性
- `0.3`：最大多样性，摘要覆盖面最广

**keywordWeight 调参指南：**
- `0`：关闭关键词加权
- `1.2`：默认，适度提升包含关键词的句子
- `2.0+`：强主题聚焦，摘要高度围绕关键词

### 文本处理

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `minSentenceLength` | `number` | `5` | 最小句子长度（字符），低于此值的句子被过滤 |
| `minClauseLength` | `number` | `3` | 最小子句长度（仅级别 1） |

## 算法架构

```
输入文本
  │
  ├─ 1. 句子分割（按 。！？； 分句，按换行分段）
  │
  ├─ 2. TF-IDF 关键词提取（字级 unigram，停用字过滤）
  │
  ├─ 3. 字级 n-gram 提取（绕过分词）
  │
  ├─ 4. TextRank 迭代
  │     初始分数 = 位置权重 × 关键词权重
  │     WS(Vi) = (1-d)×init(Vi) + d×Σ(sim(Vi,Vj)/Σsim(Vj,Vk))×WS(Vj)
  │
  ├─ 5. 句子选择
  │     ├─ 级别 1：句子级 TextRank → Top-5 句 → 子句拆分 → 子句级 TextRank → 连词处理 → 拼接
  │     ├─ 级别 2：多轮重排（两轮 TextRank）
  │     ├─ 级别 3/4：TextRank + MMR 选句
  │     └─ 级别 5：全部返回
  │
  └─ 6. 输出（按原文顺序排列）
```

### 核心算法说明

**TextRank**：本库从零实现了 TextRank 算法（未引用任何第三方 TextRank 库），将句子视为节点，字级 n-gram 相似度视为边权重，通过迭代计算每个句子的全局重要性得分。在此基础上，加入了位置先验权重和 TF-IDF 关键词权重作为初始分数，使算法更适应中文文章结构。

**位置加权**：中文文章通常遵循"首段点题、段首概括"的结构，因此首段首句、段落首句获得更高的先验权重。

**TF-IDF 关键词加权**：以句子为"文档"，统计字级 unigram 的 TF-IDF 值，提取 Top-K 关键词。包含关键词越多的句子，先验权重越高。

**MMR（Maximal Marginal Relevance）**：选句时综合考虑相关性和多样性。公式：`MMR(s) = λ×score(s) - (1-λ)×max_sim(s, 已选句子集)`。每选一句，就惩罚与已选句子过于相似的新句子。

**子句连词处理**：极致压缩时，选出的子句可能以连词开头（如"然而""也""因此"），脱离上下文后语义不完整。处理策略：如果前一个子句也被选中则保留连词，否则剥离连词及后续标点。

## 使用示例

### 基础用法

```ts
import { extractSummary } from "chinese-summary";

const text = `人工智能是计算机科学的重要分支，它致力于研究和开发用于模拟人类智能的理论和方法。
深度学习技术的出现是这一轮AI复兴的关键推动力。
自然语言处理是人工智能最活跃的研究方向之一。
然而，人工智能的快速发展也带来了一系列社会问题和伦理挑战。
展望未来，人工智能将继续深刻改变人类社会的方方面面。`;

// 各级别输出
for (const level of [1, 2, 3, 4, 5] as const) {
  const result = extractSummary(text, { compressionLevel: level });
  console.log(`级别${level}: ${result.text}`);
}
```

### 调整多样性

```ts
// 关闭 MMR（纯得分排序，等同旧版行为）
const result1 = extractSummary(text, { compressionLevel: 3, mmrLambda: 1.0 });

// 最大多样性（摘要覆盖面最广）
const result2 = extractSummary(text, { compressionLevel: 3, mmrLambda: 0.3 });
```

### 调整主题聚焦度

```ts
// 关闭关键词加权
const result1 = extractSummary(text, { compressionLevel: 3, keywordWeight: 0 });

// 强主题聚焦
const result2 = extractSummary(text, { compressionLevel: 3, keywordWeight: 2.0 });
```

### 极致压缩控制

```ts
// 压缩为 2 个子句
const result1 = extractSummary(text, { compressionLevel: 1, maxClauses: 2 });

// 压缩为 5 个子句
const result2 = extractSummary(text, { compressionLevel: 1, maxClauses: 5 });
```

### 获取句子排名（调试用）

```ts
import { rankSentences } from "chinese-summary";

const ranked = rankSentences(text);
for (const s of ranked.slice(0, 5)) {
  console.log(`[${s.score.toFixed(4)}] ${s.text}`);
}
```

### 自定义位置权重

```ts
// 强化首段首句（适合新闻类文章）
const result = extractSummary(text, {
  compressionLevel: 3,
  weightFirstSentence: 2.0,
  weightFirstParagraph: 1.5,
});

// 弱化位置权重（让 TextRank 图结构主导，适合学术论文）
const result2 = extractSummary(text, {
  compressionLevel: 3,
  weightFirstSentence: 1.0,
  weightFirstParagraph: 1.0,
  weightParagraphStart: 1.0,
  weightParagraphEnd: 1.0,
});
```

## 健壮性

库对以下场景做了完善防护，不会崩溃：

- `null` / `undefined` / 非字符串输入 → 返回空结果
- 空字符串 / 纯空白 / 纯换行 → 返回空结果
- BOM / 零宽字符 / 混合换行符 → 自动清理
