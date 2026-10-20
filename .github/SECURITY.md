# Security Policy / 安全策略

## Supported versions / 支持版本

安全修复只针对最新公开版本和 `main` 分支。旧版本用户应先升级到最新 Release。

Security fixes target the latest public release and the `main` branch. Users of older versions should upgrade to the latest release first.

| Version | Supported |
| --- | --- |
| 0.6.0 | Yes |
| 0.5.7 and earlier | No |

## Reporting a vulnerability / 报告漏洞

请优先打开仓库的 **Security** 页面并选择 **Report a vulnerability**，通过 GitHub Private Vulnerability Reporting 私下提交。

Use **Security → Report a vulnerability** in this repository to submit the report privately through GitHub Private Vulnerability Reporting.

如果该按钮不可用，请只创建一个标题为 `Security contact request` 的 Issue，请求私下联系方式。不要在公开 Issue 中提供漏洞细节、利用步骤、令牌或私人数据。

If that option is unavailable, open an issue titled `Security contact request` asking for a private contact channel. Do not include vulnerability details, exploit steps, tokens, or private data in the public issue.

报告中请包含：

- 受影响的 Wexi LoL 和 macOS 版本
- 问题影响和可重复条件
- 最小化的复现步骤或概念验证
- 任何缓解方法

Include the affected Wexi LoL and macOS versions, impact, reproducible conditions, minimal reproduction or proof of concept, and any known mitigation.

## Security scope / 安全范围

以下问题属于安全报告范围：

- 屏幕录制内容、玩家资料或本机诊断数据被意外保存或上传
- Riot 本机 HTTPS 接口的证书校验绕过
- Release、更新链接、DMG 或源码包被替换或篡改
- 任意代码执行、权限提升或未经授权的文件访问
- 令牌、Cookie、玩家身份或其他敏感数据泄露

Relevant reports include unintended storage or upload of captured content, player data, or diagnostics; bypasses of local Riot HTTPS certificate validation; release or download tampering; arbitrary code execution; privilege escalation; unauthorized file access; and exposure of tokens, cookies, player identities, or other sensitive data.

OP.GG 页面暂时不可用、统计数据过期、普通 OCR 误识别或 Overlay 轻微错位通常属于功能 Bug，请使用 Bug report 模板。

Temporary OP.GG availability, stale statistics, ordinary OCR mistakes, and minor overlay misalignment are functional bugs and should use the Bug report form.

