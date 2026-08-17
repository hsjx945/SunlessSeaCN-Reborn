# 第三方来源与许可证说明

本项目只负责兼容性整理、打包、安装/卸载脚本和测试；不包含《Sunless Sea》游戏本体，也不取得游戏原始资源的版权。

## 致谢与贡献范围

感谢前人的汉化工作。本项目不是从零翻译，也不将第三方 UI 或文本汉化声称为原创；本项目作者主要负责兼容性核对、格式/标签修复、运行环境整理、安装器、打包和测试，将已有汉化成果整合为可安装的兼容包。第三方文本、插件和翻译内容的署名与许可证仍归其原作者和上游项目所有。

## tinygrox/SunlessSeaCN

- 地址：https://github.com/tinygrox/SunlessSeaCN
- 用途：Sunless Sea UI 中文插件及运行时兼容层的来源参考。
- 仓库页面包含 GPL-3.0 LICENSE；README 同时写有 CC-BY 4.0 说明。发布包保留插件文件和上游署名，不改变上游条款；如许可证解释发生变化，应以原作者最新说明为准。

## InstantComet/SunlessSea

- 地址：https://github.com/InstantComet/SunlessSea
- 用途：文本 addon 的来源参考和汉化数据基础。
- README 说明该仓库仅包含文本汉化，并注明项目延续自 https://github.com/diskrubbish/Sunless_Sea_Chinese_Translation_Mod_Re 。当前仓库未发现独立 LICENSE 文件，因此本项目不对上游文本另行授权，也不主张其版权。

## BepInEx

- 地址：https://github.com/BepInEx/BepInEx
- 使用版本：[5.4.23.5](https://github.com/BepInEx/BepInEx/releases/tag/v5.4.23.5)
- 用途：Unity Mono Mod 加载器。
- BepInEx 按上游 LGPL-2.1 等许可证发布；源码、完整许可证和第三方依赖请以官方仓库为准。

## macOS v6.0.5 静态 UI 路线

- macOS v6.0.5 不再依赖 BepInEx/Doorstop 启动 UI 插件；它分发针对 Steam BuildID `24437295` 的 `Sunless.Game.bsdiff`、独立中文程序集、资源和文本 addon。
- 静态 UI 插件复用 [tinygrox/SunlessSeaCN](https://github.com/tinygrox/SunlessSeaCN) GPL-3.0 源码快照（commit `e9bde736554913aa835f547f28e26ed6f393d515`），并新增 macOS Bootstrap 与 Mono.Cecil 注入器。对应源码随仓库 `macos-static/` 保留，修改源应按 GPL-3.0 提供对应源码和许可证。
- Harmony 使用 [Lib.Harmony 2.4.2](https://www.nuget.org/packages/Lib.Harmony/2.4.2)，MIT 许可证。NuGet nupkg SHA-256 为 `d64592e53090464559fce48612c9ca7c8dc73113841376b7aa3455f46fc5d579`，精确来源和选用程序集哈希见 `packaging/macos/sources.lock.json`。
- macOS 包只分发 bsdiff，不分发《Sunless Sea》的完整原始或 patched `Sunless.Game.dll`；安装器在本机临时生成并校验目标程序集。

## 游戏本体

《Sunless Sea》及其原始资源版权归 Failbetter Games 及其他相关权利人所有。本项目不包含游戏本体，不代表 Failbetter Games，也不提供盗版游戏文件。
