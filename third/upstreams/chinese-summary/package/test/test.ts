/**
 * 测试：中文文本概要提取 - 多级压缩
 *
 * 运行方式：npx tsx test/test.ts
 */

import { extractSummary, rankSentences } from "../src/chinese-summary";

// ============================================================
// 测试文本
// ============================================================

const testText = "量子计算是一种利用量子力学原理进行计算的新型计算模式。" +
  "与经典计算机使用比特（0或1）不同，量子计算机使用量子比特，可以同时处于0和1的叠加态。" +
  "\n\n量子计算在密码学、药物发现、材料科学和优化问题等领域具有巨大潜力。" +
  "谷歌、IBM和微软等科技巨头都在积极投入量子计算的研究。" +
  "\n\n然而，量子计算目前仍面临许多技术挑战。" +
  "量子比特非常脆弱，容易受到环境噪声的干扰，导致计算错误。" +
  "纠错技术和量子比特的稳定性是当前研究的重点方向。" +
  "\n\n尽管如此，科学家们对量子计算的未来保持乐观。" +
  "预计在未来十到二十年内，量子计算将在特定领域实现实用化突破。";

// ============================================================
// 测试 1：所有压缩级别对比
// ============================================================

console.log("======================================================================");
console.log("多级压缩对比测试");
console.log("======================================================================");
console.log("\n原文 (" + testText.length + " 字):");
console.log(testText.replace(/\n/g, "\\n"));

const levels: number[] = [1, 2, 3, 4, 5];

for (const level of levels) {
  console.log("\n----------------------------------------------------------------------");
  console.log("[级别 " + level + "]");

  const result = extractSummary(testText, { compressionLevel: level as any });

  console.log("摘要 (" + result.text.length + " 字, " + result.summary.length + " 句):");
  console.log(result.text);

  // 级别 1 时显示子句信息
  if (level === 1 && result.clauses) {
    console.log("\n子句得分:");
    const sortedClauses = [...result.clauses].sort((a, b) => b.score - a.score);
    for (const c of sortedClauses) {
      const marker = result.text.includes(c.text.replace(/[，、,;:]/g, "")) ? "*" : " ";
      console.log("  " + marker + " [" + c.score.toFixed(4) + "] (来自句" + c.sourceSentenceIndex + ") " + c.text);
    }
  }

  const ratio = ((1 - result.text.length / testText.length) * 100).toFixed(1);
  console.log("\n压缩率: " + testText.length + "字 -> " + result.text.length + "字 (" + ratio + "%)");
}

// ============================================================
// 测试 2：旧接口兼容性（sentenceCount）
// ============================================================

console.log("\n======================================================================");
console.log("旧接口兼容性测试 (sentenceCount)");
console.log("======================================================================");

const resultOld = extractSummary(testText, { sentenceCount: 2 });
console.log("\nsentenceCount=2 -> " + resultOld.text.length + " 字, " + resultOld.summary.length + " 句");
console.log(resultOld.text);

// ============================================================
// 测试 3：级别 1 不同 maxClauses 对比
// ============================================================

console.log("\n======================================================================");
console.log("极致压缩 maxClauses 参数对比");
console.log("======================================================================");

for (const maxClauses of [2, 3, 4, 5]) {
  const result = extractSummary(testText, { compressionLevel: 1, maxClauses: maxClauses });
  console.log("\nmaxClauses=" + maxClauses + " -> " + result.text);
}

// ============================================================
// 测试 4：短文本保护
// ============================================================

console.log("\n======================================================================");
console.log("短文本保护测试");
console.log("======================================================================");

const shortText = "今天天气很好，适合出门散步。";
const shortResult = extractSummary(shortText, { compressionLevel: 1 });
console.log("短文本级别1: \"" + shortText + "\" -> \"" + shortResult.text + "\"");

// ============================================================
// 压缩率汇总
// ============================================================

console.log("\n======================================================================");
console.log("各级别压缩率汇总");
console.log("======================================================================");

for (const level of levels) {
  const result = extractSummary(testText, { compressionLevel: level as any });
  const ratio = ((1 - result.text.length / testText.length) * 100).toFixed(1);
  const barLen = Math.round(parseFloat(ratio) / 5);
  const bar = "#".repeat(barLen);
  const paddedLen = result.text.length.toString().padStart(3, " ");
  const paddedRatio = ratio.padStart(5, " ");
  console.log("  级别" + level + ": " + paddedLen + "字  压缩" + paddedRatio + "%  " + bar);
}
