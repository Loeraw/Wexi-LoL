# Contributing to Wexi LoL / 参与贡献

感谢你帮助改进 Wexi LoL。提交问题或代码前，请先搜索现有 Issues，避免重复报告。

Thank you for helping improve Wexi LoL. Before opening an issue or pull request, search the existing issues to avoid duplicates.

## 报告问题 / Reporting bugs

请使用 Bug report 模板，并尽可能提供：

- Wexi LoL 版本与 macOS 版本
- 游戏模式、游戏分辨率和窗口模式
- 显示器数量、排列方式与缩放设置
- LoL HUD、小地图缩放以及客户端语言
- 可重复的操作步骤、预期结果和实际结果

Use the Bug report form and include the Wexi LoL version, macOS version, game mode, resolution, window mode, display setup, HUD/minimap scale, client language, and reproducible steps.

请在上传日志或截图前删除 Riot ID、玩家姓名、访问令牌、Cookie 和其他私人信息。不要公开提交完整游戏截图，除非确认其中不含私人信息。

Remove Riot IDs, player names, access tokens, cookies, and other private information before attaching logs or images. Do not post full game screenshots unless you have confirmed that they contain no private information.

## 本地开发 / Local development

项目使用 Swift Package Manager，没有第三方包依赖。

The project uses Swift Package Manager and has no third-party package dependencies.

```sh
git clone https://github.com/Loeraw/Wexi-LoL.git
cd Wexi-LoL
swift test
./script/build_and_run.sh --verify
```

生成本地发布包：

Build local release artifacts:

```sh
./script/package_dmg.sh
./script/package_source.sh
```

## 修改要求 / Change requirements

- 保持应用不注入 LoL、不读取游戏进程内存、不自动点击或操作游戏。
- 屏幕识别必须在本地完成，不得保存或上传截图。
- 不要提交 Riot、OP.GG 或用户的令牌、Cookie、完整玩家身份或其他秘密。
- Overlay 位置修改应覆盖 16:9、16:10 和超宽屏回退逻辑。
- OP.GG 解析修改应安全处理缺失、过期或结构变化的数据，不得生成虚假统计。
- 新增用户可见文本时，应同步更新所有界面语言，或明确提供英文回退。

- Keep the app free of game injection, process-memory reading, and automated game input.
- Screen recognition must remain local; screenshots must not be saved or uploaded.
- Never commit Riot, OP.GG, or user tokens, cookies, complete player identities, or other secrets.
- Overlay placement changes should cover 16:9, 16:10, and ultrawide fallback behavior.
- OP.GG parser changes must fail safely on missing, stale, or changed data and must not fabricate statistics.
- When adding user-visible text, update every interface language or provide an explicit English fallback.

## Pull requests

1. 从最新的 `main` 创建功能分支。
2. 保持每个 PR 只解决一个明确问题。
3. 运行 `swift test`，并在 PR 中写明测试结果。
4. UI 或定位修改应说明测试过的分辨率、宽高比和 HUD 缩放。
5. 同步更新 README、网站或版本信息（如果改动影响用户文档）。

1. Create a feature branch from the latest `main`.
2. Keep each pull request focused on one clear problem.
3. Run `swift test` and include the result in the pull request.
4. For UI or placement changes, list the tested resolutions, aspect ratios, and HUD scales.
5. Update the README, website, or version information when the user documentation changes.

