// 职责: 应用级别编译期常量（版本号、功能开关、产品线、匿名上报地址、反馈渠道、匿名诊断公共头）
// 关联文件:
//   lib/shared/providers/trace_providers.dart
//   lib/shared/providers/anonymous_reporting_providers.dart
//   lib/shared/logger/startup_failure_reporter.dart
//   lib/shared/widgets/ai/chat/feedback_dialog.dart
//   release.sh (版本号同步)
//

/// 应用版本号。
/// 与 pubspec.yaml 的 version 字段保持同步，由 release.sh 一同更新。
/// 供需要同步获取版本号的场景使用（如匿名上报），避免 PackageInfo 异步调用。
const appVersion = '0.6.16';

/// 匿名诊断接收地址，包含完整路径；请求不追加业务 API 后缀。
/// 为空表示本构建不接匿名诊断：不上报，也不展示 opt-in 入口。
const anonymousReportingBaseUrl = '';

/// 公开仓库地址；关于页与反馈的 GitHub Issue 都指向这里。
const revericGitHubRepoUrl = 'https://github.com/zhnn456/shutong-studio';

/// QQ 交流群官方邀请链接。
const revericQqGroupJoinUrl = 'https://qm.qq.com/q/Ap8pfOWHDO';
const revericQqGroupNumber = '924148054';

/// 技能广场只读取公开链接目录，导入沿用各来源平台的现有流程。
const revericSkillsCatalogUrl =
    'https://raw.githubusercontent.com/looplj/reveric-skills/main/catalog.json';

/// 插件市场官方索引地址，由 Cloudflare R2 分发。
const revericPluginMarketplaceIndexUrl =
    'https://downloads.reveric.app/plugins/index.json';

/// 规则库热更清单地址：清单与各数据文件同目录，版本号递增即可热更。
/// 为空表示只使用安装包内置规则库，不发网络请求。
const revericRulePackManifestUrl =
    'https://raw.githubusercontent.com/zhnn456/shutong-studio/main/rule_packs/manifest.json';

/// AGPLv3 第 7 条附加条款要求修改版保留的作者署名，与 NOTICES 保持一致，不做本地化。
const revericAttribution = 'Based on Reveric by looplj.';

/// 接收私下反馈的邮箱；诊断文件含作品内容，只通过邮件而非公开 Issue 发送。
const revericFeedbackEmail = '282063152@qq.com';

/// 产品线编码，通过 X-Product-Code 请求头发送给匿名诊断接收端；
/// 客服留言的 `product` 字段也复用该编码，便于后台按软件/产品区分留言。
/// 书童AI写作 = writer；鲸喜AI = whale；后续新产品在此追加稳定编码。
const revericProductCode = 'writer';

/// 产品线展示名（提交留言时随 `product_name` 上报，供后台分组展示）。
const revericProductName = '书童AI写作';

/// 匿名诊断 API 公共请求头。
final revericApiHeaders = <String, String>{
  'Content-Type': 'application/json',
  'X-Product-Code': revericProductCode,
};

/// 用户主动提交日志与会话的诊断后端，与匿名事件上报独立。
const diagnosticsBaseUrl = 'https://diagnostics.reveric.app';

/// 构思画布的 UI、工具与内置技能入口；不影响视频制作画布。
const ideationCanvasEnabled = bool.fromEnvironment(
  'ENABLE_IDEATION_CANVAS',
  defaultValue: false,
);
