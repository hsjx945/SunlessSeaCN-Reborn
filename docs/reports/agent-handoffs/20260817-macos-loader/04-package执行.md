# macOS v6.0.5 打包与真实安装交接

## 输入基线

- Steam AppID `304650`、BuildID `24437295`、Unity `6000.3.2f1`、游戏 `2.3.0.22`。
- 原始 `Sunless.Game.dll` SHA-256：`b7d5df522b8ae7c1ee4913b283586fc4d823f735159bf00753f42ce4a86474f0`。
- 正确 Unity 6 数据根：`~/Library/Application Support/com.failbettergames.sunlesssea`。
- Windows 保持 v6.0.4；macOS 产物为 v6.0.5；未创建 tag 或 GitHub Release。

## 已完成

- 静态引导注入 `TitleScreenInit.Start`，使用 Lib.Harmony 2.4.2，并保留 tinygrox GPL-3.0 对应源码和归属。
- macOS ZIP 只包含 `Sunless.Game.bsdiff`、独立汉化程序集、Harmony、资源和 17 个 addon JSON，不包含完整原始或 patched 游戏 DLL。
- 安装器绑定原始和目标 DLL hash，使用锁、临时文件、备份、原子 manifest、失败回滚、重复安装清理和 ad-hoc 重签。
- 安装器只向 `com.failbettergames.sunlesssea` 安装 addon，不因 legacy 目录存在旧存档而选错。
- 旧 v6.0.4 清单已移动到原有 `SunlessSeaCN-backup-20260817-215644/`，未删除；正式游戏当前保持 v6.0.5 已安装状态。

## 验证

- `tests/test_macos_static_ui.sh`：通过；目标 DLL SHA-256 `80076c8ce27f5cd4121afeadf4e4ba7a7e0e266afb06b10cc01e501637677042`，15 张图片、17 个 addon 文件。
- `tests/test_macos_package.sh`：通过 ZIP 结构、Bash 3.2 语法、安装→重复安装→卸载、错误差分失败回滚、用户修改时零写入预检、原始 hash 恢复和严格签名验证。
- 真实 app：目标 DLL hash 正确，`codesign --verify --deep --strict` 通过，manifest v2 指向正确数据根。
- `Player.log`：`content probe 143942: 一名熟练的船员`，并记录 static bootstrap/Harmony 已初始化。
- 真实主菜单已观察到“无光之海 / 新游戏 / 载入游戏 / 设置 / 制作人员 / 退出到桌面”。
- legacy Autosave SHA-256 仍为 `5700a5888e4327bc1bd4e3df0acb23ce4aac751e5b3dae581a7bd06b18a4b181`。
- 最终 ZIP：5,469,323 bytes，SHA-256 `a8b04fa05a7b15a282fb9b9216319c6a2bc66f9ac0b74ad73f72a65e3c7e6c47`，48 entries；包含 GPL-3.0 和 Harmony MIT 完整许可证。

## 风险与未完成

- 当前 UI 自动化能截图和 hover，但 Unity 全屏没有接受模拟 click/keypress，因此尚未取得事件 144628 的真实界面截图。数据文件中该事件为“创建你的船长”，运行时探针已证明同一 addon 被仓库合并，但最终剧情 UI 仍保留一项人工点击验收。
- Steam 更新导致原始 DLL hash 变化时，安装器会拒绝；需重新构建新差分。
- 旧 BepInEx 文件仍在游戏根目录，但正式 v6.0.5 不引用它们；未自动删除，避免扩大清理范围。

## 经验候选

- 症状：UI 中文但剧情/地点仍英文。
- 原始证据：addon 安装在 legacy `unity.Failbetter Games.Sunless Sea`；Unity 6 的 `Application.persistentDataPath` 实际为 `com.failbettergames.sunlesssea`；正确目录后运行时事件探针返回中文。
- 已验证根因：旧安装器按“已存在目录”选择了不再被当前 Unity 6 读取的数据根。
- 可复用修复：安装器绑定当前 Unity 数据根；不要以 legacy saves 目录存在作为选择依据；加入运行时内容探针。
- 验证结果：真实游戏日志、主菜单、hash、签名、存档和沙箱往返均通过；剧情事件最终 UI 截图待人工点击。
- 适用范围：本 BuildID/Unity 6 macOS 版本；不能据此推断其他 Unity 版本使用同一 bundle 数据路径。

## 路由评测

- 实际角色：researcher、planner、luna_deep、verifier；主代理整合并修正安装器往返缺陷。
- 选择理由：加载链、程序集注入、事务安装和真实 UI 验收是互相依赖的多阶段任务。
- 一次完成：否；沙箱发现 `Managed/Managed` 记录路径、重复安装 hash 检查顺序和卸载后资源签名三处返工。
- 验收：静态/包测试通过；真实运行大部分通过，剧情 UI 人工截图待补。
- 耗时与用量：-。
- 建议：后续同类包仍使用 luna_deep；事务安装器必须保留完整往返测试，不建议降为机械 quick 修改。
