/**
 * 长文本测试：中文文本概要提取 - 多级压缩
 *
 * 运行方式：npx tsx test/test-long.ts
 */

import { extractSummary, rankSentences } from "../src/chinese-summary";

// ============================================================
// 测试文本（约2000字）
// ============================================================

const testText =
  "人工智能（Artificial Intelligence，简称AI）是计算机科学的一个重要分支，" +
  "它致力于研究和开发用于模拟、延伸和扩展人类智能的理论、方法、技术及应用系统。" +
  "人工智能的发展可以追溯到20世纪50年代，当时一批具有远见卓识的科学家开始探索" +
  "能否让机器像人一样思考和学习。\n\n" +

  "1956年夏天，达特茅斯学院举行了一次具有历史意义的研讨会，" +
  '约翰·麦卡锡、马文·明斯基、克劳德·香农等学者首次提出了"人工智能"这一概念。' +
  "这次会议被认为是人工智能学科诞生的标志，标志着人类开始系统地研究智能机器的可能性。" +
  '在随后的几十年里，人工智能经历了几次高潮和低谷，被称为"AI寒冬"的时期曾让许多研究者失去了信心。\n\n' +

  "进入21世纪后，随着计算能力的大幅提升、大数据的积累以及算法的突破，" +
  "人工智能迎来了前所未有的发展机遇。深度学习技术的出现是这一轮AI复兴的关键推动力。" +
  "2012年，杰弗里·辛顿的团队在ImageNet图像识别竞赛中取得了突破性成绩，" +
  "将错误率降低了近十个百分点，震惊了整个学术界和产业界。" +
  "此后，深度学习在语音识别、自然语言处理、计算机视觉等领域不断刷新纪录。\n\n" +

  "2016年，谷歌DeepMind团队开发的AlphaGo以4比1的比分击败了世界围棋冠军李世石，" +
  "这一事件在全球范围内引发了广泛关注和讨论。" +
  "围棋被认为是人类最复杂的棋类游戏之一，其可能的棋局数量超过宇宙中的原子总数。" +
  "AlphaGo的胜利不仅证明了AI在复杂决策任务上的能力，" +
  '也标志着人工智能从"窄AI"向"通用AI"迈出了重要一步。\n\n' +

  "自然语言处理是人工智能最活跃的研究方向之一。" +
  "2018年，谷歌推出了BERT模型，开创了预训练语言模型的先河。" +
  "随后，GPT系列模型不断刷新自然语言理解和生成的能力边界。" +
  "2022年底，ChatGPT的发布更是引发了全球性的AI应用热潮，" +
  "让普通大众第一次真切地感受到人工智能的强大能力。" +
  "大语言模型展现出的涌现能力，即模型规模达到一定程度后突然出现的新能力，" +
  "成为学术界和产业界共同关注的热点问题。\n\n" +

  "然而，人工智能的快速发展也带来了一系列社会问题和伦理挑战。" +
  "首先是就业问题，自动化和智能化可能导致大量传统岗位被机器取代，" +
  "尤其是重复性劳动和低技能工作面临的风险最大。" +
  "其次是隐私问题，AI系统需要大量数据进行训练，" +
  "而这些数据往往包含个人隐私信息，如何在技术发展和隐私保护之间取得平衡是一个重要课题。" +
  "第三是算法偏见问题，训练数据中的偏见可能被AI系统放大，" +
  "导致对某些群体的不公平对待。\n\n" +

  "此外，AI的安全性和可控性也引发了广泛担忧。" +
  "深度伪造技术可以生成极其逼真的虚假视频和音频，" +
  "可能被用于制造虚假信息、实施诈骗等违法活动。" +
  "自主武器系统的开发也引发了关于AI是否应该被用于军事目的的激烈辩论。" +
  "许多科学家和企业家，包括斯蒂芬·霍金和埃隆·马斯克，" +
  "都曾公开警告过不受控制的人工智能可能带来的潜在威胁。\n\n" +

  "面对这些挑战，各国政府和国际组织开始制定AI治理框架和伦理准则。" +
  "欧盟于2023年通过了《人工智能法案》，成为全球首个对AI进行全面立法的地区。" +
  "中国也出台了《生成式人工智能服务管理暂行办法》，" +
  "对AI内容的生成和传播进行规范。美国则通过行政令的方式，" +
  "要求大型AI系统在发布前进行安全评估。" +
  "如何在促进AI创新和确保安全可控之间找到平衡，" +
  "成为各国政策制定者面临的核心难题。\n\n" +

  "展望未来，人工智能将继续深刻改变人类社会的方方面面。" +
  "在医疗领域，AI辅助诊断和药物研发有望大幅提升医疗效率和精准度。" +
  "在教育领域，个性化学习系统可以根据每个学生的特点定制教学方案。" +
  "在交通领域，自动驾驶技术正在逐步成熟，有望减少交通事故和拥堵。" +
  "在科学研究领域，AI正在成为科学家的强大工具，" +
  "帮助他们在蛋白质结构预测、新材料发现等方面取得突破性进展。" +
  "人工智能的未来充满希望，但也需要人类以审慎和负责任的态度来引导其发展方向。";

// ============================================================
// 测试：所有压缩级别
// ============================================================

console.log("======================================================================");
console.log("长文本多级压缩测试 (" + testText.length + " 字)");
console.log("======================================================================");

const levels: number[] = [1, 2, 3, 4, 5];

for (const level of levels) {
  console.log("\n----------------------------------------------------------------------");
  console.log("[级别 " + level + "]");

  const result = extractSummary(testText, { compressionLevel: level as any });

  console.log("摘要 (" + result.text.length + " 字, " + result.summary.length + " 句):");
  console.log(result.text);

  // 级别 1 时显示子句信息
  if (level === 1 && result.clauses) {
    console.log("\n子句得分 Top-5:");
    const sortedClauses = [...result.clauses].sort((a, b) => b.score - a.score);
    for (let i = 0; i < Math.min(5, sortedClauses.length); i++) {
      const c = sortedClauses[i];
      const marker = result.text.includes(c.text.replace(/[，、,;:]/g, "")) ? "*" : " ";
      console.log("  " + marker + " [" + c.score.toFixed(4) + "] " + c.text);
    }
  }

  const ratio = ((1 - result.text.length / testText.length) * 100).toFixed(1);
  console.log("\n压缩率: " + testText.length + "字 -> " + result.text.length + "字 (" + ratio + "%)");
}

// ============================================================
// 级别 1 不同 maxClauses 对比
// ============================================================

console.log("\n======================================================================");
console.log("极致压缩 maxClauses 参数对比");
console.log("======================================================================");

for (const maxClauses of [2, 3, 4, 5, 6]) {
  const result = extractSummary(testText, { compressionLevel: 1, maxClauses: maxClauses });
  const ratio = ((1 - result.text.length / testText.length) * 100).toFixed(1);
  console.log("\nmaxClauses=" + maxClauses + " (" + result.text.length + "字, 压缩" + ratio + "%):");
  console.log("  " + result.text);
}

// ============================================================
// 句子得分排名（调试用）
// ============================================================

console.log("\n======================================================================");
console.log("句子得分排名 Top-10");
console.log("======================================================================");

const ranked = rankSentences(testText);
for (let i = 0; i < Math.min(10, ranked.length); i++) {
  const s = ranked[i];
  const posTag = [
    s.isFirstParagraph && s.isParagraphStart ? "首段首句" : "",
    s.isFirstParagraph && !s.isParagraphStart ? "首段" : "",
    !s.isFirstParagraph && s.isParagraphStart ? "段首" : "",
    s.isParagraphEnd ? "段尾" : "",
  ].filter(Boolean).join("+");

  console.log("  " + (i + 1) + ". [" + s.score.toFixed(4) + "] " + (posTag ? "(" + posTag + ") " : "") + s.text.substring(0, 60) + (s.text.length > 60 ? "..." : ""));
}

// ============================================================
// 压缩率汇总
// ============================================================

console.log("\n======================================================================");
console.log("各级别压缩率汇总");
console.log("======================================================================");

for (const level of levels) {
  const result = extractSummary(testText, { compressionLevel: level as any });
  const ratio = ((1 - result.text.length / testText.length) * 100).toFixed(1);
  const barLen = Math.max(0, Math.round(parseFloat(ratio) / 2));
  const bar = "#".repeat(barLen);
  const paddedLen = result.text.length.toString().padStart(4, " ");
  const paddedRatio = ratio.padStart(5, " ");
  console.log("  级别" + level + ": " + paddedLen + "字  压缩" + paddedRatio + "%  " + bar);
}
