/**
 * 健壮性测试：验证各种边界输入和特殊字符不会导致崩溃
 *
 * 运行方式：npx tsx test/test-robust.ts
 */

import { extractSummary, rankSentences } from "../src/chinese-summary";

let passCount = 0;
let failCount = 0;

function assert(condition: boolean, label: string): void {
  if (condition) {
    passCount++;
    console.log("  PASS: " + label);
  } else {
    failCount++;
    console.log("  FAIL: " + label);
  }
}

// ============================================================
// 1. 空值 / 非法输入
// ============================================================

console.log("======================================================================");
console.log("1. 空值 / 非法输入");
console.log("======================================================================");

assert(extractSummary(null as any).text === "", "null -> 空结果");
assert(extractSummary(undefined as any).text === "", "undefined -> 空结果");
assert(extractSummary(123 as any).text === "", "数字 123 -> 空结果");
assert(extractSummary("").text === "", "空字符串 -> 空结果");
assert(extractSummary("   ").text === "", "纯空白 -> 空结果");
assert(extractSummary("\n\n\n").text === "", "纯换行 -> 空结果");
assert(extractSummary("\t\t").text === "", "纯制表符 -> 空结果");

// ============================================================
// 2. 特殊字符
// ============================================================

console.log("\n======================================================================");
console.log("2. 特殊字符");
console.log("======================================================================");

// BOM + 零宽字符
const bomText = "\uFEFF\u200B\u200C\u200D\u00AD人工智能是计算机科学的重要分支。";
const bomResult = extractSummary(bomText);
assert(bomResult.text.length > 0, "BOM + 零宽字符 -> 正常处理");
assert(!bomResult.text.includes("\uFEFF"), "BOM 被移除");

// 中文引号
const quoteText = '所谓"人工智能"，是指模拟人类智能的技术。';
const quoteResult = extractSummary(quoteText);
assert(quoteResult.text.length > 0, "中文引号 -> 正常处理");

// 各种括号
const bracketText = "《人工智能法案》（AI Act）于2023年通过。";
const bracketResult = extractSummary(bracketText);
assert(bracketResult.text.length > 0, "书名号+圆括号 -> 正常处理");

// 特殊 Unicode
const unicodeText = "AI\u3000技术\u00A0发展\u2026\u2026非常重要。";
const unicodeResult = extractSummary(unicodeText);
assert(unicodeResult.text.length > 0, "全角空格+省略号 -> 正常处理");

// 混合换行符
const mixedNewline = "第一段内容。\r\n第二段内容。\r第三段内容。";
const mixedResult = extractSummary(mixedNewline);
assert(mixedResult.text.length > 0, "混合换行符(\\r\\n/\\r/\\n) -> 正常处理");

// Emoji
const emojiText = "人工智能发展迅速\uD83D\uDE80，未来可期\uD83C\uDF1F。";
const emojiResult = extractSummary(emojiText);
assert(emojiResult.text.length > 0, "Emoji -> 正常处理");

// HTML 实体残留
const htmlText = "AI&nbsp;技术&nbsp;发展。";
const htmlResult = extractSummary(htmlText);
assert(htmlResult.text.length > 0, "HTML 实体 -> 正常处理");

// ============================================================
// 3. 极端参数
// ============================================================

console.log("\n======================================================================");
console.log("3. 极端参数");
console.log("======================================================================");

const normalText = "人工智能是计算机科学的重要分支。深度学习推动了AI的快速发展。自然语言处理取得了突破性进展。";

assert(extractSummary(normalText, { compressionLevel: 0 as any }).text.length > 0, "compressionLevel=0 -> 自动修正");
assert(extractSummary(normalText, { compressionLevel: 99 as any }).text.length > 0, "compressionLevel=99 -> 自动修正");
assert(extractSummary(normalText, { compressionLevel: -1 as any }).text.length > 0, "compressionLevel=-1 -> 自动修正");
assert(extractSummary(normalText, { compressionLevel: 1.5 as any }).text.length > 0, "compressionLevel=1.5 -> 自动修正");
assert(extractSummary(normalText, { ngramSize: 0 as any }).text.length > 0, "ngramSize=0 -> 自动修正");
assert(extractSummary(normalText, { ngramSize: 100 as any }).text.length > 0, "ngramSize=100 -> 自动修正");
assert(extractSummary(normalText, { dampingFactor: 0 as any }).text.length > 0, "dampingFactor=0 -> 自动修正");
assert(extractSummary(normalText, { dampingFactor: 2 as any }).text.length > 0, "dampingFactor=2 -> 自动修正");
assert(extractSummary(normalText, { maxIterations: 0 as any }).text.length > 0, "maxIterations=0 -> 自动修正");
assert(extractSummary(normalText, { minSentenceLength: -1 as any }).text.length > 0, "minSentenceLength=-1 -> 自动修正");
assert(extractSummary(normalText, { maxClauses: 0 as any }).text.length > 0, "maxClauses=0 -> 自动修正");
assert(extractSummary(normalText, { sentenceCount: NaN as any }).text.length > 0, "sentenceCount=NaN -> 自动修正");
assert(extractSummary(normalText, { sentenceCount: Infinity as any }).text.length > 0, "sentenceCount=Infinity -> 自动修正");
assert(extractSummary(normalText, { weightFirstSentence: NaN as any }).text.length > 0, "weightFirstSentence=NaN -> 自动修正");

// ============================================================
// 4. 极短文本
// ============================================================

console.log("\n======================================================================");
console.log("4. 极短文本");
console.log("======================================================================");

assert(extractSummary("你好").text === "", "2字文本 -> 空结果(低于minSentenceLength)");
assert(extractSummary("你好世界！").text.length > 0, "5字文本 -> 正常处理");

// 单句
const oneSentence = "人工智能是计算机科学的一个重要分支，它致力于研究和开发用于模拟人类智能的理论和方法。";
const oneResult = extractSummary(oneSentence, { compressionLevel: 1 });
assert(oneResult.text.length > 0, "单句级别1 -> 正常处理");

// 单段多句
const onePara = "人工智能发展迅速。深度学习推动了技术进步。自然语言处理取得突破。";
const oneParaResult = extractSummary(onePara, { compressionLevel: 3 });
assert(oneParaResult.text.length > 0, "单段3句级别3 -> 正常处理");

// ============================================================
// 5. 无句末标点的文本
// ============================================================

console.log("\n======================================================================");
console.log("5. 无句末标点的文本");
console.log("======================================================================");

const noPunctText = "人工智能发展迅速深度学习推动了技术进步自然语言处理取得突破";
const noPunctResult = extractSummary(noPunctText);
assert(noPunctResult.text.length > 0, "无句末标点 -> 整段作为一个句子");

// ============================================================
// 6. 纯英文 / 纯数字 / 混合
// ============================================================

console.log("\n======================================================================");
console.log("6. 纯英文 / 纯数字 / 混合");
console.log("======================================================================");

const englishText = "Artificial intelligence is a branch of computer science. Deep learning has driven rapid progress. NLP has achieved breakthroughs.";
const englishResult = extractSummary(englishText);
assert(englishResult.text.length > 0, "纯英文 -> 正常处理");

const mixedText = "AI(Artificial Intelligence)是计算机科学的branch。Deep Learning推动了发展。";
const mixedCnEnResult = extractSummary(mixedText);
assert(mixedCnEnResult.text.length > 0, "中英混合 -> 正常处理");

// ============================================================
// 7. 重复文本
// ============================================================

console.log("\n======================================================================");
console.log("7. 重复文本");
console.log("======================================================================");

const repeatText = "人工智能很重要。人工智能很重要。人工智能很重要。人工智能很重要。人工智能很重要。";
const repeatResult = extractSummary(repeatText, { compressionLevel: 3 });
assert(repeatResult.text.length > 0, "完全重复句子 -> 正常处理");

// ============================================================
// 8. rankSentences 健壮性
// ============================================================

console.log("\n======================================================================");
console.log("8. rankSentences 健壮性");
console.log("======================================================================");

assert(rankSentences(null as any).length === 0, "rankSentences(null) -> 空数组");
assert(rankSentences("").length === 0, "rankSentences('') -> 空数组");
assert(rankSentences(42 as any).length === 0, "rankSentences(42) -> 空数组");
assert(rankSentences(normalText).length > 0, "rankSentences(正常文本) -> 有结果");

// ============================================================
// 9. 结果完整性校验
// ============================================================

console.log("\n======================================================================");
console.log("9. 结果完整性校验");
console.log("======================================================================");

const fullText = "人工智能是计算机科学的重要分支。深度学习推动了AI的快速发展。自然语言处理取得了突破性进展。计算机视觉也在不断进步。强化学习在游戏领域表现出色。";

for (const level of [1, 2, 3, 4, 5] as const) {
  const result = extractSummary(fullText, { compressionLevel: level });
  assert(result.summary.length > 0, "级别" + level + ": summary 非空");
  assert(result.sentences.length > 0, "级别" + level + ": sentences 非空");
  assert(typeof result.text === "string", "级别" + level + ": text 是字符串");
  assert(result.compressionLevel === level, "级别" + level + ": compressionLevel 正确");
  assert(result.text === result.summary.join(" "), "级别" + level + ": text === summary.join(' ')");

  // 所有句子得分应为有限数
  const allFinite = result.sentences.every((s) => Number.isFinite(s.score));
  assert(allFinite, "级别" + level + ": 所有句子得分为有限数");
}

// ============================================================
// 10. 子句拼接标点去重
// ============================================================

console.log("\n======================================================================");
console.log("10. 子句拼接标点去重");
console.log("======================================================================");

const punctText =
  "人工智能是计算机科学的重要分支，它致力于研究和开发用于模拟人类智能的理论和方法。" +
  "深度学习技术的出现是这一轮AI复兴的关键推动力，2012年辛顿团队在ImageNet竞赛中取得突破。" +
  "自然语言处理是人工智能最活跃的研究方向之一，BERT和GPT模型不断刷新能力边界。" +
  "然而，人工智能的快速发展也带来了一系列社会问题和伦理挑战。" +
  "展望未来，人工智能将继续深刻改变人类社会的方方面面。";

const punctResult = extractSummary(punctText, { compressionLevel: 1, maxClauses: 5 });
assert(!punctResult.text.includes("。，"), "无 。， 重复标点");
assert(!punctResult.text.includes("，，"), "无 ，， 重复标点");
assert(punctResult.text.length > 0, "标点去重后仍有内容");
console.log("  级别1结果: " + punctResult.text);

// ============================================================
// 汇总
// ============================================================

console.log("\n======================================================================");
console.log("测试汇总");
console.log("======================================================================");
console.log("  PASS: " + passCount);
console.log("  FAIL: " + failCount);
console.log("  TOTAL: " + (passCount + failCount));

if (failCount > 0) {
  process.exit(1);
}
