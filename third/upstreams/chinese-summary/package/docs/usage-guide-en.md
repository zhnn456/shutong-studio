[中文](./usage-guide.md)

# chinese-summary Usage Guide

Chinese text summarization library — Detailed documentation

> Copyright (c) 2025 Beijing Fengtong Technology Co., Ltd.
> Authors: Guo Yufeng, Wu Qiong
> License: MIT

## Features

- **Zero Dependencies**: Pure TypeScript, no tokenizer or AI model required
- **Character-level n-gram**: Bypasses Chinese word segmentation, uses character sliding window for similarity
- **5 Compression Levels**: From "no compression" to "extreme compression into one sentence"
- **Positional Weighting**: First-paragraph first-sentence, paragraph start/end sentences get higher prior weights
- **TF-IDF Keyword Weighting**: Sentences containing full-text keywords receive extra weight, more topical summaries
- **MMR Redundancy Removal**: Balances relevance and diversity during sentence selection
- **Clause Conjunction Handling**: Auto-strips orphaned conjunctions during extreme compression, ensuring readability
- **Robustness**: Comprehensive input validation, parameter checking, and numeric safety

## Installation

```bash
npm install chinese-summary
```

Or import directly from source:

```ts
import { extractSummary, rankSentences } from "./src/chinese-summary";
```

## Build

The project provides four build artifacts covering all use cases:

| File | Format | Environment |
|------|--------|-------------|
| `dist/chinese-summary.cjs` | CJS | Node.js `require()` |
| `dist/chinese-summary.mjs` | ESM | Node.js `import`, browser `<script type="module">` |
| `dist/chinese-summary.iife.js` | IIFE | Browser `<script>` tag, global variable `ChineseSummary` |
| `dist/chinese-summary.d.ts` | Type Declaration | TypeScript IntelliSense |

```bash
# Build
npm run build
```

## Usage

### Node.js (CJS)

```js
const { extractSummary, rankSentences } = require("chinese-summary");

const text = "人工智能是计算机科学的重要分支。深度学习推动了AI的快速发展。自然语言处理取得了突破性进展。";

const result = extractSummary(text, { compressionLevel: 3 });
console.log(result.text);
```

### Node.js (ESM)

```ts
import { extractSummary, rankSentences } from "chinese-summary";

const text = "人工智能是计算机科学的重要分支。深度学习推动了AI的快速发展。自然语言处理取得了突破性进展。";

const result = extractSummary(text, { compressionLevel: 3 });
console.log(result.text);
```

### Browser (IIFE — `<script>` tag)

```html
<script src="dist/chinese-summary.iife.js"></script>
<script>
  var text = "人工智能是计算机科学的重要分支。深度学习推动了AI的快速发展。";
  var result = ChineseSummary.extractSummary(text, { compressionLevel: 2 });
  console.log(result.text);
</script>
```

> The IIFE version exposes `extractSummary` and `rankSentences` via the global variable `ChineseSummary`.

### Browser (ES Module)

```html
<script type="module">
  import { extractSummary } from "./dist/chinese-summary.mjs";

  const text = document.querySelector("article").textContent;
  const result = extractSummary(text, { compressionLevel: 2 });
  console.log(result.text);
</script>
```

### npm + Bundler (Webpack / Vite / Rollup)

```ts
import { extractSummary } from "chinese-summary";

const result = extractSummary(text, { compressionLevel: 2 });
```

## Quick Start

```ts
import { extractSummary } from "chinese-summary";

const text = "人工智能是计算机科学的重要分支，它致力于研究和开发用于模拟人类智能的理论和方法。深度学习技术的出现是这一轮AI复兴的关键推动力。自然语言处理是人工智能最活跃的研究方向之一。然而，人工智能的快速发展也带来了一系列社会问题和伦理挑战。展望未来，人工智能将继续深刻改变人类社会的方方面面。";

// Default: Level 3 (moderate compression, ~30% sentences)
const result = extractSummary(text);
console.log(result.text);
// → "人工智能是计算机科学的重要分支，它致力于研究和开发用于模拟人类智能的理论和方法。 自然语言处理是人工智能最活跃的研究方向之一。"

// Extreme compression: condense into one sentence
const extreme = extractSummary(text, { compressionLevel: 1 });
console.log(extreme.text);
// → "人工智能是计算机科学的重要分支，自然语言处理取得了突破性进展"

// Specify sentence count (legacy API)
const legacy = extractSummary(text, { sentenceCount: 2 });
console.log(legacy.text);
```

## Compression Levels

| Level | Description | Strategy | Use Case |
|-------|-------------|----------|----------|
| 1 | Extreme | Clause-level extraction, merged into one sentence | Title generation, push notifications |
| 2 | High | ~20% sentences + multi-round reranking | Short summaries, list previews |
| 3 | Moderate | ~30% sentences (**Default**) | General summaries |
| 4 | Light | ~50% sentences | Long summaries, speed reading |
| 5 | None | Return all sentences | Sorting only, debugging |

Compression example (1584-character AI article):

| Level | Chars | Compression Ratio |
|-------|-------|-------------------|
| 1 | 69 | 95.6% |
| 2 | 408 | 74.2% |
| 3 | 536 | 66.2% |
| 4 | 886 | 44.1% |
| 5 | 1603 | -1.2% |

## API

### `extractSummary(text, options?)`

Extract Chinese text summary.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `text` | `string` | Yes | Original Chinese text |
| `options` | `SummaryOptions` | No | Configuration options |

**Returns:** `SummaryResult`

```ts
interface SummaryResult {
  summary: string[];          // Summary sentences (in original order)
  sentences: SentenceInfo[];  // All sentences with scores
  text: string;               // Summary text (sentences joined by space)
  compressionLevel: 1|2|3|4|5;
  clauses?: ClauseInfo[];     // Clause info (level 1 only)
}
```

```ts
interface ClauseInfo {
  text: string;               // Clause text
  sourceSentenceIndex: number;// Source sentence index
  clauseIndex: number;        // Index within source sentence
  isMainClause: boolean;      // Whether it's the main clause (first clause)
  score: number;              // TextRank score
}
```

### `rankSentences(text, options?)`

Get sentence score rankings only, no summary extraction. For debugging and analysis.

**Returns:** `SentenceInfo[]` (descending by score)

```ts
interface SentenceInfo {
  index: number;              // Global sentence index
  text: string;               // Sentence text
  paragraphIndex: number;     // Paragraph index
  sentenceInParagraph: number;// Index within paragraph
  isParagraphStart: boolean;  // Is paragraph start sentence
  isParagraphEnd: boolean;    // Is paragraph end sentence
  isFirstParagraph: boolean;  // Is in first paragraph
  score: number;              // TextRank score
}
```

## Configuration Options

### Compression Control

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `compressionLevel` | `1\|2\|3\|4\|5` | `3` | Compression level, mutually exclusive with `sentenceCount`, higher priority |
| `sentenceCount` | `number` | `3` | Summary sentence count (legacy API, only effective when `compressionLevel` is not specified) |
| `maxClauses` | `number` | `3` | Max clauses for extreme compression (level 1 only) |

### TextRank Algorithm

| Option | Type | Default | Range | Description |
|--------|------|---------|-------|-------------|
| `ngramSize` | `number` | `2` | 1-5 | n-gram size, 2=bigram |
| `dampingFactor` | `number` | `0.85` | 0.1-0.95 | Damping factor d |
| `maxIterations` | `number` | `30` | 1-200 | Max iterations |
| `convergenceThreshold` | `number` | `0.0001` | 1e-8~1 | Convergence threshold |

### Positional Weights

| Option | Type | Default | Range | Description |
|--------|------|---------|-------|-------------|
| `weightFirstSentence` | `number` | `1.5` | 0.5-5 | First-paragraph first-sentence weight |
| `weightFirstParagraph` | `number` | `1.2` | 0.5-5 | First-paragraph other-sentence weight |
| `weightParagraphStart` | `number` | `1.1` | 0.5-5 | Paragraph start-sentence weight |
| `weightParagraphEnd` | `number` | `1.05` | 0.5-5 | Paragraph end-sentence weight |

Weights are multiplicative. For example: first-paragraph first-sentence = `weightFirstSentence`, first-paragraph other sentences = `weightFirstParagraph`, non-first-paragraph start sentences = `weightParagraphStart`, paragraph end sentences get an additional multiplier of `weightParagraphEnd`.

### Diversity & Keywords

| Option | Type | Default | Range | Description |
|--------|------|---------|-------|-------------|
| `mmrLambda` | `number` | `0.7` | 0.3-1.0 | MMR diversity coefficient λ (levels 2-4 only) |
| `keywordWeight` | `number` | `1.2` | 0-5 | Keyword weight coefficient, 0=off |

**mmrLambda Tuning Guide:**
- `1.0`: Pure score ranking, MMR off (same as legacy behavior)
- `0.7`: Default, balanced relevance and diversity
- `0.3`: Maximum diversity, broadest summary coverage

**keywordWeight Tuning Guide:**
- `0`: Disable keyword weighting
- `1.2`: Default, moderate boost for keyword-containing sentences
- `2.0+`: Strong topic focus, summary highly centered on keywords

### Text Processing

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `minSentenceLength` | `number` | `5` | Min sentence length (chars), shorter sentences are filtered |
| `minClauseLength` | `number` | `3` | Min clause length (level 1 only) |

## Algorithm Architecture

```
Input Text
  │
  ├─ 1. Sentence splitting (by 。！？；, paragraphs by newline)
  │
  ├─ 2. TF-IDF keyword extraction (char-level unigram, stop-char filtering)
  │
  ├─ 3. Character-level n-gram extraction (bypasses segmentation)
  │
  ├─ 4. TextRank Iteration
  │     Initial score = positional weight × keyword weight
  │     WS(Vi) = (1-d)×init(Vi) + d×Σ(sim(Vi,Vj)/Σsim(Vj,Vk))×WS(Vj)
  │
  ├─ 5. Sentence Selection
  │     ├─ Level 1: Sentence-level TextRank → Top-5 → clause splitting → clause-level TextRank → conjunction handling → merge
  │     ├─ Level 2: Multi-round reranking (two rounds of TextRank)
  │     ├─ Levels 3-4: TextRank + MMR selection
  │     └─ Level 5: Return all
  │
  └─ 6. Output (in original order)
```

### Core Algorithm Description

**TextRank**: This library implements TextRank from scratch (no third-party TextRank library). Sentences are treated as nodes, character-level n-gram similarity as edge weights, and global importance scores are computed through iteration. Positional prior weights and TF-IDF keyword weights are added as initial scores to better adapt to Chinese article structure.

**Positional Weighting**: Chinese articles typically follow the structure of "first paragraph states the theme, paragraph starts summarize." Therefore, first-paragraph first-sentences and paragraph start-sentences receive higher prior weights.

**TF-IDF Keyword Weighting**: Sentences are treated as "documents," character-level unigram TF-IDF values are computed, and Top-K keywords are extracted. Sentences containing more keywords receive higher prior weights.

**MMR (Maximal Marginal Relevance)**: During sentence selection, relevance and diversity are both considered. Formula: `MMR(s) = λ×score(s) - (1-λ)×max_sim(s, selected set)`. Each time a sentence is selected, new sentences too similar to already-selected ones are penalized.

**Clause Conjunction Handling**: During extreme compression, selected clauses may start with conjunctions (e.g., "然而", "也", "因此"), which are semantically incomplete out of context. Strategy: if the preceding clause is also selected, keep the conjunction; otherwise, strip the conjunction and following punctuation.

## Usage Examples

### Basic Usage

```ts
import { extractSummary } from "chinese-summary";

const text = `人工智能是计算机科学的重要分支，它致力于研究和开发用于模拟人类智能的理论和方法。
深度学习技术的出现是这一轮AI复兴的关键推动力。
自然语言处理是人工智能最活跃的研究方向之一。
然而，人工智能的快速发展也带来了一系列社会问题和伦理挑战。
展望未来，人工智能将继续深刻改变人类社会的方方面面。`;

// Output at each level
for (const level of [1, 2, 3, 4, 5] as const) {
  const result = extractSummary(text, { compressionLevel: level });
  console.log(`Level ${level}: ${result.text}`);
}
```

### Adjust Diversity

```ts
// Disable MMR (pure score ranking, same as legacy)
const result1 = extractSummary(text, { compressionLevel: 3, mmrLambda: 1.0 });

// Maximum diversity (broadest summary coverage)
const result2 = extractSummary(text, { compressionLevel: 3, mmrLambda: 0.3 });
```

### Adjust Topic Focus

```ts
// Disable keyword weighting
const result1 = extractSummary(text, { compressionLevel: 3, keywordWeight: 0 });

// Strong topic focus
const result2 = extractSummary(text, { compressionLevel: 3, keywordWeight: 2.0 });
```

### Extreme Compression Control

```ts
// Compress into 2 clauses
const result1 = extractSummary(text, { compressionLevel: 1, maxClauses: 2 });

// Compress into 5 clauses
const result2 = extractSummary(text, { compressionLevel: 1, maxClauses: 5 });
```

### Get Sentence Rankings (for debugging)

```ts
import { rankSentences } from "chinese-summary";

const ranked = rankSentences(text);
for (const s of ranked.slice(0, 5)) {
  console.log(`[${s.score.toFixed(4)}] ${s.text}`);
}
```

### Custom Positional Weights

```ts
// Strengthen first-sentence weight (for news articles)
const result = extractSummary(text, {
  compressionLevel: 3,
  weightFirstSentence: 2.0,
  weightFirstParagraph: 1.5,
});

// Weaken positional weights (let TextRank graph structure dominate, for academic papers)
const result2 = extractSummary(text, {
  compressionLevel: 3,
  weightFirstSentence: 1.0,
  weightFirstParagraph: 1.0,
  weightParagraphStart: 1.0,
  weightParagraphEnd: 1.0,
});
```

## Robustness

The library has comprehensive safeguards for the following scenarios and will not crash:

- `null` / `undefined` / non-string input → returns empty result
- Empty string / whitespace-only / newlines-only → returns empty result
- BOM / zero-width chars / mixed line endings → auto-cleaned
