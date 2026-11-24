[中文](./test-report.md)

# chinese-summary Test Report

> Test Date: 2026-06-16
> Environment: Node.js + tsx
> Version: chinese-summary@1.0.0

## Test Overview

| Test File | Cases | Passed | Failed | Result |
|-----------|-------|--------|--------|--------|
| `test/test.ts` — Basic | 5 groups | 5 groups | 0 | PASS |
| `test/test-robust.ts` — Robustness | 74 cases | 74 cases | 0 | PASS |
| `test/test-long.ts` — Long text | 3 groups | 3 groups | 0 | PASS |
| **Total** | **82 cases/groups** | **82** | **0** | **ALL PASS** |

---

## 1. Basic Functionality Tests (test/test.ts)

### 1.1 Multi-level Compression Comparison

Test text is a 261-character quantum computing introduction (4 paragraphs, 9 sentences), output at each level:

| Level | Output Chars | Sentences | Compression Ratio | Description |
|-------|-------------|-----------|-------------------|-------------|
| 1 | 57 | — | 78.2% | Extreme compression, clause-level extraction merged into one sentence |
| 2 | 50 | 2 | 80.8% | High compression, multi-round reranking |
| 3 | 95 | 3 | 63.6% | Moderate compression, TextRank + MMR |
| 4 | 144 | 5 | 44.8% | Light compression, ~50% sentences retained |
| 5 | 263 | 9 | -0.8% | No compression, sorting only (slight increase due to space joining) |

**Level 1 Clause Scores:**

| Score | Source Sentence | Clause Text |
|-------|----------------|-------------|
| 1.5202 | S3 | IBM和微软等科技巨头都在积极投入量子计算的研究。 |
| 1.4217 | S4 | 量子计算目前仍面临许多技术挑战。 |
| 1.1595 | S1 | 与经典计算机使用比特（0或1）不同， |
| 0.2855 | S7 | 尽管如此， |
| 0.2668 | S3 | 谷歌、 |
| 0.2612 | S4 | 然而， |
| 0.2214 | S1 | 可以同时处于0和1的叠加态。 |

> Conjunctions "尽管如此，" and "然而，" are auto-stripped to ensure readability.

### 1.2 Legacy API Compatibility (sentenceCount)

| Parameter | Output Chars | Sentences |
|-----------|-------------|-----------|
| `sentenceCount=2` | 67 | 2 |

> Legacy API `sentenceCount` works normally; `compressionLevel` takes priority when both are specified.

### 1.3 Extreme Compression maxClauses Comparison

| maxClauses | Output |
|------------|--------|
| 2 | 量子计算是一种利用量子力学原理进行计算的新型计算模式。量子计算机使用量子比特， |
| 3 | 量子计算是一种利用量子力学原理进行计算的新型计算模式。量子计算机使用量子比特，科学家们对量子计算的未来保持乐观。 |
| 4 | 量子计算是一种利用量子力学原理进行计算的新型计算模式。量子计算机使用量子比特，IBM和微软等科技巨头都在积极投入量子计算的研究。科学家们对量子计算的未来保持乐观。 |
| 5 | 量子计算是一种利用量子力学原理进行计算的新型计算模式。量子计算机使用量子比特，IBM和微软等科技巨头都在积极投入量子计算的研究。量子计算目前仍面临许多技术挑战。科学家们对量子计算的未来保持乐观。 |

### 1.4 Short Text Protection

| Input | Output |
|-------|--------|
| "今天天气很好，适合出门散步。" | "今天天气很好，适合出门散步。" |

> Short text (only 1 sentence) is returned as-is at level 1, with no content loss.

---

## 2. Robustness Tests (test/test-robust.ts)

74 assertions total, all passed. Distribution by category:

### 2.1 Null / Invalid Input (7 cases)

| Case | Expected Behavior | Result |
|------|-------------------|--------|
| `null` | Returns empty result | PASS |
| `undefined` | Returns empty result | PASS |
| Number `123` | Returns empty result | PASS |
| Empty string `""` | Returns empty result | PASS |
| Whitespace only `"   "` | Returns empty result | PASS |
| Newlines only `"\n\n\n"` | Returns empty result | PASS |
| Tabs only `"\t\t"` | Returns empty result | PASS |

### 2.2 Special Characters (8 cases)

| Case | Expected Behavior | Result |
|------|-------------------|--------|
| BOM + zero-width chars | Handled normally | PASS |
| BOM removed | BOM not in output | PASS |
| Chinese quotes `""` | Handled normally | PASS |
| Book title + parentheses `《》()` | Handled normally | PASS |
| Full-width space + ellipsis | Handled normally | PASS |
| Mixed line endings `\r\n/\r/\n` | Handled normally | PASS |
| Emoji | Handled normally | PASS |
| HTML entity `&nbsp;` | Handled normally | PASS |

### 2.3 Extreme Parameters (14 cases)

| Case | Expected Behavior | Result |
|------|-------------------|--------|
| `compressionLevel=0` | Auto-corrected to valid value | PASS |
| `compressionLevel=99` | Auto-corrected to valid value | PASS |
| `compressionLevel=-1` | Auto-corrected to valid value | PASS |
| `compressionLevel=1.5` | Auto-corrected to valid value | PASS |
| `ngramSize=0` | Auto-corrected to default | PASS |
| `ngramSize=100` | Auto-corrected to default | PASS |
| `dampingFactor=0` | Auto-corrected to default | PASS |
| `dampingFactor=2` | Auto-corrected to default | PASS |
| `maxIterations=0` | Auto-corrected to default | PASS |
| `minSentenceLength=-1` | Auto-corrected to default | PASS |
| `maxClauses=0` | Auto-corrected to default | PASS |
| `sentenceCount=NaN` | Auto-corrected to default | PASS |
| `sentenceCount=Infinity` | Auto-corrected to default | PASS |
| `weightFirstSentence=NaN` | Auto-corrected to default | PASS |

### 2.4 Very Short Text (4 cases)

| Case | Expected Behavior | Result |
|------|-------------------|--------|
| 2-char text "你好" | Empty result (below minSentenceLength) | PASS |
| 5-char text "你好世界！" | Handled normally | PASS |
| Single sentence at level 1 | Handled normally | PASS |
| Single paragraph 3 sentences at level 3 | Handled normally | PASS |

### 2.5 No Sentence-ending Punctuation (1 case)

| Case | Expected Behavior | Result |
|------|-------------------|--------|
| Text without ending punctuation | Entire text treated as one sentence | PASS |

### 2.6 Pure English / Mixed (2 cases)

| Case | Expected Behavior | Result |
|------|-------------------|--------|
| Pure English | Handled normally | PASS |
| Chinese-English mixed | Handled normally | PASS |

### 2.7 Repeated Text (1 case)

| Case | Expected Behavior | Result |
|------|-------------------|--------|
| Completely repeated sentences | Handled normally | PASS |

### 2.8 rankSentences Robustness (4 cases)

| Case | Expected Behavior | Result |
|------|-------------------|--------|
| `rankSentences(null)` | Returns empty array | PASS |
| `rankSentences('')` | Returns empty array | PASS |
| `rankSentences(42)` | Returns empty array | PASS |
| `rankSentences(normal text)` | Returns non-empty array | PASS |

### 2.9 Result Integrity Checks (25 cases)

Verified for each of 5 compression levels, 5 assertions per level:

| Check | L1 | L2 | L3 | L4 | L5 |
|-------|----|----|----|----|-----|
| `summary` non-empty | PASS | PASS | PASS | PASS | PASS |
| `sentences` non-empty | PASS | PASS | PASS | PASS | PASS |
| `text` is string | PASS | PASS | PASS | PASS | PASS |
| `compressionLevel` correct | PASS | PASS | PASS | PASS | PASS |
| `text === summary.join(' ')` | PASS | PASS | PASS | PASS | PASS |
| All scores are finite | PASS | PASS | PASS | PASS | PASS |

### 2.10 Clause Merge Punctuation Dedup (3 cases)

| Check | Result |
|-------|--------|
| No `。，` duplicate punctuation | PASS |
| No `，，` duplicate punctuation | PASS |
| Content remains after dedup | PASS |

---

## 3. Long Text Tests (test/test-long.ts)

Test text is a 1584-character AI history article (8 paragraphs, 20+ sentences).

### 3.1 Compression Results at Each Level

| Level | Output Chars | Sentences | Compression Ratio | Description |
|-------|-------------|-----------|-------------------|-------------|
| 1 | 69 | — | 95.6% | Extreme compression, 3 clauses merged into one sentence |
| 2 | 408 | — | 74.2% | High compression, multi-round reranking |
| 3 | 536 | — | 66.2% | Moderate compression, TextRank + MMR |
| 4 | 886 | — | 44.1% | Light compression, ~50% sentences retained |
| 5 | 1603 | — | -1.2% | No compression, sorting only (slight increase due to space joining) |

### 3.2 Extreme Compression maxClauses Comparison

| maxClauses | Output Chars | Compression Ratio |
|------------|-------------|-------------------|
| 2 | 49 | 96.9% |
| 3 | 69 | 95.6% |
| 4 | 94 | 94.1% |
| 5 | 116 | 92.7% |
| 6 | 145 | 90.8% |

### 3.3 Sentence Score Ranking Top-10

| Rank | Score | Position | Sentence (first 60 chars) |
|------|-------|----------|---------------------------|
| 1 | 2.1302 | 1st-para 1st-sent | 人工智能（Artificial Intelligence，简称AI）是计算机科学的一个重... |
| 2 | 2.0271 | — | 2022年底，ChatGPT的发布更是引发了全球性的AI应用热潮，让普通大... |
| 3 | 1.7314 | — | 欧盟于2023年通过了《人工智能法案》，成为全球首个对AI进行全面立... |
| 4 | 1.7042 | Para end | AlphaGo的胜利不仅证明了AI在复杂决策任务上的能力，也标志着人工... |
| 5 | 1.7024 | — | 这次会议被认为是人工智能学科诞生的标志，标志着人类开始系统地研究... |
| 6 | 1.6668 | 1st-para + para end | 人工智能的发展可以追溯到20世纪50年代，当时一批具有远见卓识的科... |
| 7 | 1.5541 | Para start | 自然语言处理是人工智能最活跃的研究方向之一。 |
| 8 | 1.5183 | Para start | 然而，人工智能的快速发展也带来了一系列社会问题和伦理挑战。 |
| 9 | 1.4769 | — | 中国也出台了《生成式人工智能服务管理暂行办法》，对AI内容的生成和... |
| 10 | 1.4715 | Para start | 进入21世纪后，随着计算能力的大幅提升、大数据的积累以及算法的突破... |

> Positional weighting is effective: the first-paragraph first-sentence has the highest score (2.1302), and paragraph start/end sentences generally rank higher.

---

## 4. Test Conclusions

1. **Functional Completeness**: 5 compression levels, legacy sentenceCount API, maxClauses parameter, and rankSentences ranking all work correctly.

2. **Robustness**: All 74 edge cases passed. The library has comprehensive safeguards for null/undefined/empty strings/special characters/extreme parameters/very short texts and will not crash.

3. **Compression Effect**: Using a 1584-character article as example, level 3 (default) compresses to 536 chars (66.2% ratio), level 1 extreme compression to 69 chars (95.6% ratio). Compression ratios at all levels meet design expectations.

4. **Positional Weighting**: First-paragraph first-sentences and paragraph start/end sentences score significantly higher than middle sentences, consistent with the Chinese article structure of "first paragraph states the theme, paragraph starts summarize."

5. **Clause Conjunction Handling**: During extreme compression, orphaned conjunctions (e.g., "然而，", "尽管如此，") are correctly stripped, ensuring output readability.

6. **Punctuation Dedup**: No duplicate punctuation such as `。，` or `，，` appears during clause merging.
