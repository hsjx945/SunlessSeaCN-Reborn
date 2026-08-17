# Sunless Sea macOS 汉化路线调研

## 结论

Steam BuildID 24437295 使用 Unity 6000.3.2f1 Mono。汉化由两层组成：

- `addon` JSON：剧情、地点、人物、物品等内容。游戏原生读取，不需要 mod loader。
- Managed UI：主菜单、设置、HUD 和硬编码字符串。需要运行时 Harmony，或对当前版本程序集加入静态引导。

本机对官方 BepInEx 5.4.23.5 和 gib 的必要 macOS workaround 做了隔离实跑。游戏可启动，但没有生成 BepInEx 日志或配置，因此本版本停止 Doorstop 路线，改用当前程序集静态引导；不得继续把“文件已复制”当成加载成功。

## 一手来源与采用范围

| 项目 | 固定版本 | 许可证 | 采用 | 不采用 |
| --- | --- | --- | --- | --- |
| [tinygrox/SunlessSeaCN](https://github.com/tinygrox/SunlessSeaCN) | `e9bde736554913aa835f547f28e26ed6f393d515` | GPL-3.0；README 另有 CC BY 4.0 表述 | UI Harmony 源码及翻译资源，保留源码和归属 | Windows-only `BepInProcess("Sunless Sea.exe")` |
| [InstantComet/SunlessSea](https://github.com/InstantComet/SunlessSea) | 当前 v6.0.4 已锁定的现有 payload | 未发现独立 LICENSE | 维持既有简中 addon 与署名 | 不扩大许可声明 |
| [kaosensei/sunless-sea-zh-tw](https://github.com/kaosensei/sunless-sea-zh-tw) | `124a8e440a5bc6f4cebdf5791b92067d4aa17971` | 翻译文本 CC BY-NC-SA 4.0 | macOS addon 路径与实际加载经验 | 不复制繁中翻译文本或二进制 |
| [BepInEx/BepInEx](https://github.com/BepInEx/BepInEx/releases/tag/v5.4.23.5) | `v5.4.23.5` | LGPL-2.1 等上游条款 | 官方 loader 对照探针 | 本机失败后不进入最终方案 |
| [toebeann/gib](https://github.com/toebeann/gib) | `e344b0b5d0397cc73ebf916ed6040612eecb318c` | ISC | `cd "$BASEDIR"`、app 路径与 Rosetta 验收经验 | 不运行其 Steam 写入流程，不默认移除签名 |

官方 BepInEx macOS 包：`BepInEx_macos_universal_5.4.23.5.zip`，658168 bytes，SHA-256 `01c2ae782eb016dfd6c345a18dbd2dcafffb3d9d318449d6486689f426b4a323`。

## 实机证据

- 游戏：`Sunless Sea.app`，可执行名 `Sunless Sea`，Mach-O universal x86_64/arm64。
- `Sunless.Game.dll`：77392384 bytes，SHA-256 `b7d5df522b8ae7c1ee4913b283586fc4d823f735159bf00753f42ce4a86474f0`。
- Unity 6000.3.2f1 / 游戏 2.3.0.22 的实际数据根已变为
  `~/Library/Application Support/com.failbettergames.sunlesssea/`。旧目录
  `unity.Failbetter Games.Sunless Sea` 仍可能保留旧存档，但新版不会从那里加载 addon。
- 简中 addon 必须安装到
  `~/Library/Application Support/com.failbettergames.sunlesssea/addon/Sunless_sea_CN_reborn/`。
  运行时探针已确认事件 143942 加载为“一名熟练的船员”；放在旧目录时同一事件为英文。
- v6.0.2/v6.0.4 的 macOS installer 在 Bash 3.2 + `set -u` 下会因同一 `local` 声明读取 `rel` 而中断并留下空 manifest。
- 官方 BepInEx 包和旧补丁中的 `libdoorstop.dylib` SHA-256 均为 `cb4aaa97bd9a08178ac2d165b33284b744d18498d5dec5a07fc2b6f6d87d80b9`，不是漏库或错误库。
- 官方包、Rosetta、gib 必要 runner 修正的隔离运行未产生 `BepInEx/LogOutput.log` 或配置；游戏本身正常启动，Autosave SHA-256 前后均为 `5700a5888e4327bc1bd4e3df0acb23ce4aac751e5b3dae581a7bd06b18a4b181`。

## 选择

最终 macOS 包采用“原生 addon + 当前精确 hash 的 Managed 差分补丁 + standalone Harmony bootstrap”。安装器必须拒绝未知游戏 DLL，先 staging、验证目标 hash、备份、原子替换，并在失败时恢复。包内不得分发完整游戏程序集。
