# Sunless Sea 中文补丁 / Sunless Sea CN Reborn Pack

这是一个面向《Sunless Sea》的社区中文兼容打包项目，当前版本为 **6.0.0**。

它把已经验证可用的 BepInEx UI 插件、文本 addon、Windows 安装器和 macOS 安装器整理成可分发包。项目不包含《Sunless Sea》游戏本体或游戏原始资源，使用前请先合法拥有并安装游戏。

## 下载

请从 GitHub Releases 下载：

- `SunlessSeaCN-Windows-v6.0.0.zip`：Windows 双击安装/卸载
- `SunlessSeaCN-macOS-v6.0.0.zip`：macOS 双击安装/卸载

Windows 安装器会自动备份被覆盖的文件，并支持重复安装和卸载恢复。macOS 包使用 BepInEx 5.4.23.5 macOS universal loader；macOS 运行时需要在 Mac 上首次启动验证。

## 安装

### Windows

1. 解压 Windows 压缩包。
2. 双击 `Install-SunlessSeaCN.cmd`。
3. 启动游戏。

找不到 Steam 游戏目录时，可设置 `SUNLESS_SEA_GAME_ROOT`，或直接运行 `Install-SunlessSeaCN.ps1 -GameRoot <游戏目录>`。

### macOS

1. 解压 macOS 压缩包。
2. 双击 `Install-SunlessSeaCN.command`。
3. 启动 Steam 中的 Sunless Sea。

脚本会探测 Steam 游戏目录和常见的 Unity 数据目录。若 macOS 阻止脚本，右键选择“打开”，或在终端执行 `chmod u+x *.command *.sh`。

## 当前内容

- BepInEx 5.4.23.5
- `SunlessSeaChineseTranslation` UI/运行时插件 6.0.0
- `Sunless_sea_CN_reborn` 文本 addon，共 17 个 JSON 文件
- Windows/macOS 安装、卸载、备份和重复安装处理
- 已修复的高优先级文本问题：`Don't panic`、两处 `<i>...</i>` 富文本标签

## 测试记录

- Windows 临时目录：安装、重复安装、备份、卸载恢复通过。
- 真实 Windows Steam 安装：游戏启动后日志确认插件加载并应用 Harmony。
- macOS：安装器和 BepInEx shell 脚本通过语法检查；压缩包保留 macOS 脚本可执行权限，包含 17 个 addon JSON，未混入 Windows `winhttp.dll`。
- macOS 游戏运行时无法在 Windows 上模拟，需 Mac 实机首次启动确认。

## 参考与致谢

本项目是兼容性整理和分发工程，不声称拥有第三方内容的版权。

- UI 插件参考：[tinygrox/SunlessSeaCN](https://github.com/tinygrox/SunlessSeaCN)。该项目 README 说明其为 UI 中文补丁，并注明部分翻译参考 Instant Comet；仓库包含 GPL-3.0 LICENSE，同时 README 写有 CC-BY 4.0 说明，因此请以其仓库中的最新许可证和作者说明为准。
- 文本 addon 参考：[InstantComet/SunlessSea](https://github.com/InstantComet/SunlessSea)，其 README 说明这是文本汉化项目，并列出 [diskrubbish 的前身项目](https://github.com/diskrubbish/Sunless_Sea_Chinese_Translation_Mod_Re)。该仓库当前未发现独立 LICENSE 文件，原作者署名应保留。
- Mod 加载器使用 [BepInEx 5.4.23.5](https://github.com/BepInEx/BepInEx/releases/tag/v5.4.23.5)，其许可证和源码以官方仓库为准。
- 游戏版权归 Failbetter Games 及相关权利人所有。本项目与 Failbetter Games 无关。

详见 [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)。

## 许可证范围

本仓库原创的打包脚本、安装/卸载脚本和说明文档使用 [`LICENSE-ORIGINAL.txt`](LICENSE-ORIGINAL.txt)。第三方插件、BepInEx 和汉化文本不适用该许可证，分别受其上游条款约束。
