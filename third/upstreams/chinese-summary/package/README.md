[English](./README_EN.md)

# chinese-summary

[![npm version](https://img.shields.io/npm/v/chinese-summary.svg)](https://www.npmjs.com/package/chinese-summary)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> 不调 AI、不装分词器、不联网——纯算法 5 级压缩，把长文变一句话

中文文本概要提取库 — 纯机器算法，无 AI 依赖，零外部依赖。

基于 TextRank + 位置加权 + TF-IDF 关键词加权 + MMR 多样性选句，支持 5 级压缩，可将长文压缩为一句话。

## 为什么需要 chinese-summary？

想象一下：你在构建一个信息流应用，每天要处理上万篇中文文章。你需要给每篇文章生成摘要，但问题来了：

**场景 1：AI 摘要太贵太慢**

```
调用 GPT-4 生成一篇摘要：0.3~1 秒，$0.01~0.05
每天 10,000 篇文章：$100~500/天，$3,000~15,000/月
而且网络延迟、API 限流、服务中断……生产环境根本扛不住
```

**场景 2：中文分词是个坑**

```
"南京市长江大桥" → 分词错误 → 摘要语义完全跑偏
"从小学到大学" → "从小/学到/大学" 还是 "从/小学/到/大学"？
装分词器、维护词典、处理歧义……成本远超摘要本身
```

**场景 3：不同场景需要不同粒度**

```
推送通知：需要一句话（10 字以内）
列表预览：需要短摘要（50~100 字）
详情页速读：需要中等摘要（200~500 字）
你不想为每种场景调一次 AI，更不想维护三套摘要逻辑
```

chinese-summary 完美解决了这些问题：

| 问题 | AI 摘要服务 | chinese-summary |
|------|-----------|----------------|
| 成本 | $0.01~0.05/篇，月费数千 | **零成本**，纯本地计算 |
| 速度 | 300ms~1s/篇（网络延迟） | **<5ms/篇**，纯 CPU 计算 |
| 中文分词 | 依赖分词器，歧义难处理 | **字级 n-gram**，绕过分词 |
| 粒度控制 | 每种粒度需单独调用 | **5 级压缩**，一个参数搞定 |
| 离线可用 | 必须联网 | **零网络依赖**，离线运行 |
| 部署复杂 | API Key、配额、限流 | `npm install` 即用 |

## 特性

- **零外部依赖** — 纯 TypeScript 实现，无需分词器、无需 AI 模型
- **字级 n-gram** — 绕过中文分词，直接按字符滑动窗口计算相似度
- **5 级压缩** — 从"不压缩"到"极致压缩为一句话"，灵活控制摘要长度
- **位置加权** — 首段首句、段落首尾句获得更高先验权重
- **TF-IDF 关键词加权** — 包含全文关键词的句子获得额外权重
- **MMR 去冗余** — 选句时兼顾相关性和多样性，避免语义重复
- **子句连词处理** — 极致压缩时自动剥离脱离上下文的连词
- **健壮性** — 完善的输入校验、参数校验、数值安全防护

## 安装

```bash
npm install chinese-summary
```

## 使用方式

### Node.js（ESM）

```ts
import { extractSummary, rankSentences } from "chinese-summary";

const text = "人工智能是计算机科学的重要分支。深度学习推动了AI的快速发展。自然语言处理取得了突破性进展。";

// 默认：级别 3（中度压缩，约 30% 句子）
const result = extractSummary(text);
console.log(result.text);

// 极致压缩：压缩为一句话
const extreme = extractSummary(text, { compressionLevel: 1 });
console.log(extreme.text);

// 指定句子数量（兼容旧接口）
const legacy = extractSummary(text, { sentenceCount: 2 });
console.log(legacy.text);
```

### Node.js（CJS）

```js
const { extractSummary, rankSentences } = require("chinese-summary");

const result = extractSummary(text, { compressionLevel: 3 });
console.log(result.text);
```

### 浏览器（IIFE）

```html
<script src="node_modules/chinese-summary/dist/chinese-summary.iife.js"></script>
<script>
  var result = ChineseSummary.extractSummary(text, { compressionLevel: 2 });
  console.log(result.text);
</script>
```

### 浏览器（ES Module）

```html
<script type="module">
  import { extractSummary } from "./node_modules/chinese-summary/dist/chinese-summary.mjs";
  const result = extractSummary(text, { compressionLevel: 2 });
</script>
```

## 压缩级别

| 级别 | 说明 | 压缩策略 | 适用场景 |
|------|------|----------|----------|
| 1 | 极致压缩 | 子句级提取，拼接为一句话 | 标题生成、推送摘要 |
| 2 | 高度压缩 | 约 20% 句子 + 多轮重排 | 短摘要、列表预览 |
| 3 | 中度压缩 | 约 30% 句子（**默认**） | 通用摘要 |
| 4 | 轻度压缩 | 约 50% 句子 | 长摘要、速读 |
| 5 | 不压缩 | 返回全部句子 | 仅排序、调试 |

压缩效果示例（1584 字 AI 文章）：

| 级别 | 输出字数 | 压缩率 |
|------|----------|--------|
| 1 | 69 字 | 95.6% |
| 2 | 408 字 | 74.2% |
| 3 | 536 字 | 66.2% |
| 4 | 886 字 | 44.1% |
| 5 | 1603 字 | -1.2% |

## API

### `extractSummary(text, options?)`

提取中文文本概要，返回 `SummaryResult`：

```ts
interface SummaryResult {
  summary: string[];          // 摘要句子（按原文顺序）
  sentences: SentenceInfo[];  // 所有句子及其得分
  text: string;               // 摘要文本（句子间用空格连接）
  compressionLevel: 1|2|3|4|5;
  clauses?: ClauseInfo[];     // 子句信息（仅级别 1）
}
```

### `rankSentences(text, options?)`

仅获取句子得分排名，不提取摘要。返回 `SentenceInfo[]`（按得分降序）。

## 配置选项

### 压缩控制

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `compressionLevel` | `1\|2\|3\|4\|5` | `3` | 压缩级别，与 `sentenceCount` 互斥 |
| `sentenceCount` | `number` | `3` | 摘要句子数（旧接口） |
| `maxClauses` | `number` | `3` | 极致压缩最大子句数（仅级别 1） |

### TextRank 算法

| 选项 | 类型 | 默认值 | 范围 | 说明 |
|------|------|--------|------|------|
| `ngramSize` | `number` | `2` | 1-5 | n-gram 大小 |
| `dampingFactor` | `number` | `0.85` | 0.1-0.95 | 阻尼系数 |
| `maxIterations` | `number` | `30` | 1-200 | 最大迭代次数 |
| `convergenceThreshold` | `number` | `0.0001` | 1e-8~1 | 收敛阈值 |

### 位置权重

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `weightFirstSentence` | `number` | `1.5` | 首段首句权重 |
| `weightFirstParagraph` | `number` | `1.2` | 首段其他句权重 |
| `weightParagraphStart` | `number` | `1.1` | 段落首句权重 |
| `weightParagraphEnd` | `number` | `1.05` | 段落末句权重 |

### 多样性与关键词

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `mmrLambda` | `number` | `0.7` | MMR 多样性系数 λ（0.3-1.0） |
| `keywordWeight` | `number` | `1.2` | 关键词权重系数（0=关闭） |

## 更多示例

### 示例 1：5 级压缩对比

```ts
import { extractSummary } from "chinese-summary";

const article = `人工智能是计算机科学的一个重要分支，旨在研究和开发能够模拟人类智能的系统。
深度学习是人工智能的核心技术之一，通过多层神经网络自动学习数据特征。
自然语言处理让计算机能够理解和生成人类语言，已取得突破性进展。
计算机视觉使机器能够"看见"并理解图像和视频内容。
强化学习通过试错和奖励机制，让智能体在环境中自主学习最优策略。
大语言模型的出现标志着人工智能进入新纪元，展现出强大的涌现能力。
AI 在医疗领域的应用日益广泛，从影像诊断到药物研发都在加速变革。
自动驾驶技术融合了感知、决策和控制，是AI落地的标志性场景。
AI 伦理问题引发全球关注，算法偏见和数据隐私成为焦点议题。
未来人工智能将与人类深度协作，推动社会生产力的跨越式发展。`;

// 级别 1：极致压缩——一句话抓住核心
const lv1 = extractSummary(article, { compressionLevel: 1 });
console.log("【级别1】", lv1.text);
// → 人工智能是重要分支 深度学习是核心技术 大语言模型标志新纪元

// 级别 3：中度压缩——通用摘要
const lv3 = extractSummary(article, { compressionLevel: 3 });
console.log("【级别3】", lv3.text);
// → 人工智能是计算机科学的一个重要分支... 深度学习是人工智能的核心技术之一...
//    大语言模型的出现标志着人工智能进入新纪元...

// 级别 5：不压缩——仅排序
const lv5 = extractSummary(article, { compressionLevel: 5 });
console.log("【级别5】共", lv5.summary.length, "句");
// → 共 10 句（全部保留，按 TextRank 得分排序）
```

### 示例 2：推送通知一句话摘要

```ts
// 移动端推送场景：标题 + 一句话摘要
const news = `国务院新闻办公室今日举行新闻发布会，介绍了2025年上半年国民经济运行情况。
数据显示，上半年国内生产总值同比增长5.2%，经济运行延续恢复向好态势。
其中，高技术制造业增加值同比增长8.9%，新质生产力加快培育。
消费市场持续回暖，社会消费品零售总额同比增长7.1%。
就业形势总体稳定，城镇新增就业678万人。`;

const push = extractSummary(news, { compressionLevel: 1, maxClauses: 2 });
console.log("推送摘要:", push.text);
// → 上半年GDP同比增长5.2% 经济运行延续恢复向好态势
```

### 示例 3：句子排名——找出文章核心句

```ts
import { rankSentences } from "chinese-summary";

const text = `量子计算是未来计算技术的革命性方向。量子比特利用叠加态实现并行计算。
量子纠错是实用化的关键挑战。谷歌宣布实现量子霸权引发广泛关注。
IBM 推出1000+量子比特处理器。量子计算在密码学和药物研发领域前景广阔。`;

const ranked = rankSentences(text);

console.log("=== 句子排名 Top 5 ===");
ranked.slice(0, 5).forEach((s, i) => {
  console.log(`#${i + 1} [${s.score.toFixed(4)}] ${s.text}`);
});
// #1 [0.1823] 量子计算是未来计算技术的革命性方向
// #2 [0.1651] 量子计算在密码学和药物研发领域前景广阔
// #3 [0.1538] 量子比特利用叠加态实现并行计算
// ...
```

### 示例 4：新闻文章——强化首段首句

```ts
// 新闻文章的导语通常包含最核心信息
// 增大首段首句权重，确保导语被选中
const newsArticle = `今日，中国人民银行宣布下调存款准备金率0.5个百分点。
此次降准将释放长期流动性约1万亿元，旨在支持实体经济发展。
市场分析人士认为，此举将有效降低银行负债成本。
受此消息影响，A股三大指数午后集体拉升，沪指涨超1.5%。
债券市场收益率普遍下行，10年期国债收益率跌破2.6%。`;

const result = extractSummary(newsArticle, {
  compressionLevel: 2,
  weightFirstSentence: 2.5,  // 强力提升首句权重
  weightFirstParagraph: 1.8,  // 首段其他句也提升
});
console.log(result.text);
// 首句"降准0.5个百分点"几乎一定会被选中
```

### 示例 5：学术论文——高多样性摘要

```ts
// 学术论文通常涉及多个方面，需要摘要覆盖不同主题
const paper = `本文提出了一种基于Transformer的多模态融合方法。
实验在COCO和Flickr30K数据集上进行，结果表明本方法优于现有基线。
消融实验验证了跨模态注意力机制的有效性。
计算复杂度分析表明，本方法的推理速度满足实时要求。
本方法在视频理解和图像描述任务上也有良好的泛化能力。
未来工作将探索更高效的蒸馏策略以降低部署成本。`;

const result = extractSummary(paper, {
  compressionLevel: 3,
  mmrLambda: 0.3,  // 0.3 = 最大多样性，避免选语义重复的句子
});
console.log(result.text);
// 摘要会覆盖：方法提出 → 实验结果 → 未来展望（而非只选实验相关的句子）
```

### 示例 6：批量处理——信息流摘要生成

```ts
// 信息流场景：批量生成摘要，零成本、毫秒级
const articles = [
  { id: 1, title: "AI 新突破", content: "..." },
  { id: 2, title: "量子计算进展", content: "..." },
  { id: 3, title: "新能源政策", content: "..." },
  // ... 10,000 篇
];

const summaries = articles.map(article => {
  const result = extractSummary(article.content, { compressionLevel: 2 });
  return { id: article.id, summary: result.text };
});

// 10,000 篇文章，纯 CPU 处理 < 1 分钟
// 成本：$0（对比 AI 摘要 $100~500/天）
```

### 示例 7：与 LLM 协同——先压缩再理解

```ts
import { extractSummary } from "chinese-summary";

// 策略：先用 chinese-summary 快速压缩，再喂给 LLM 做深度理解
// 好处：大幅减少 Token 消耗，同时保留关键信息
const longArticle = "..."; // 5000 字长文

// 第一步：chinese-summary 压缩到 ~500 字
const compressed = extractSummary(longArticle, { compressionLevel: 3 });

// 第二步：将压缩后的文本喂给 LLM
const prompt = `请基于以下文章摘要，回答问题：
${compressed.text}

问题：这篇文章的核心观点是什么？`;

// Token 消耗：500 字 vs 5000 字，节省 90%
```

### 示例 8：浏览器端实时摘要

```html
<script src="node_modules/chinese-summary/dist/chinese-summary.iife.js"></script>
<script>
  // 用户选中页面文字，实时生成一句话摘要
  document.addEventListener('mouseup', () => {
    const selection = window.getSelection().toString();
    if (selection.length > 100) {
      const result = ChineseSummary.extractSummary(selection, {
        compressionLevel: 1,
        maxClauses: 2
      });
      showTooltip(result.text);  // "人工智能推动变革 量子计算前景广阔"
    }
  });
</script>
```

### 示例 9：自定义算法参数

```ts
// 调整多样性：0.3=最大多样性，1.0=纯得分排序
extractSummary(text, { compressionLevel: 3, mmrLambda: 0.3 });

// 调整主题聚焦度：0=关闭，2.0+=强聚焦
extractSummary(text, { compressionLevel: 3, keywordWeight: 2.0 });

// 极致压缩为 5 个子句
extractSummary(text, { compressionLevel: 1, maxClauses: 5 });

// 获取句子排名（调试用）
const ranked = rankSentences(text);
ranked.slice(0, 5).forEach(s => console.log(`[${s.score.toFixed(4)}] ${s.text}`));

// 强化首段首句（适合新闻）
extractSummary(text, { compressionLevel: 3, weightFirstSentence: 2.0 });
```

## 构建产物

| 文件 | 格式 | 适用环境 |
|------|------|----------|
| `dist/chinese-summary.cjs` | CJS | Node.js `require()` |
| `dist/chinese-summary.mjs` | ESM | Node.js `import`、浏览器 `<script type="module">` |
| `dist/chinese-summary.iife.js` | IIFE | 浏览器 `<script>` 标签，全局变量 `ChineseSummary` |
| `dist/chinese-summary.d.ts` | 类型声明 | TypeScript 智能提示 |

## 从源码构建

```bash
git clone https://github.com/cn-dev/chinese-summary.git
cd chinese-summary
npm install
npm run build
```

## 运行测试

```bash
# 基础功能测试
npx tsx test/test.ts

# 长文本测试（约 2000 字）
npx tsx test/test-long.ts

# 健壮性测试（74 项边界用例）
npx tsx test/test-robust.ts
```

## 算法说明

本库从零实现了 TextRank 算法（未引用任何第三方库），在此基础上加入了：

- **位置先验权重** — 首段首句、段落首尾句获得更高初始分数
- **TF-IDF 关键词加权** — 以句子为文档，字级 unigram 提取关键词，包含关键词的句子获得额外权重
- **MMR 多样性选句** — `MMR(s) = λ×score(s) - (1-λ)×max_sim(s, 已选集)`，避免语义重复
- **子句连词处理** — 极致压缩时自动剥离脱离上下文的连词（如"然而""因此"）

## 项目结构

```
chinese-summary/
├── src/
│   └── chinese-summary.ts    # 核心源码（单文件，约 1200 行）
├── dist/                      # 构建产物
├── test/
│   ├── test.ts                # 基础功能测试
│   ├── test-long.ts           # 长文本测试
│   └── test-robust.ts         # 健壮性测试（74 项）
├── docs/
│   ├── usage-guide.md         # 详细使用指南
│   └── test-report.md         # 测试报告
├── tsconfig.json              # TypeScript 配置
├── tsup.config.ts             # 构建配置
└── package.json
```

## License

MIT License

Copyright (c) 2025 北京锋通科技有限公司

Authors: 郭玉峰, 吴琼
