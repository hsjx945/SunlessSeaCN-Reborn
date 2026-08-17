# macOS loader 排错记录

## 症状

v6.0.2/v6.0.4 在 macOS 安装后仍显示英文；初次安装甚至没有复制 BepInEx。

## 已验证根因与范围

1. `/bin/bash` 3.2 在 `set -u` 下执行同一条 `local rel=... dest=...` 时，`dest` 会读取尚未完成赋值的 `rel` 并以 `unbound variable` 中断。旧安装器先截断 manifest，因此现场留下 0-byte manifest。
2. tinygrox 插件限制进程名为 `Sunless Sea.exe`，macOS 实际名为 `Sunless Sea`。这会在 Chainloader 已启动时跳过插件，但不能解释完全没有 BepInEx 日志。
3. 官方 BepInEx 5.4.23.5、Rosetta x86_64、gib 的 `cd "$BASEDIR"` 和 app 路径修正已在隔离 staging 实跑。游戏进入主菜单，但 staging 中没有 `BepInEx/LogOutput.log`、config 或 Chainloader 证据。
4. 自研 bridge/interpose 能调用 `Doorstop.Entrypoint.Start()`，仍没有 Chainloader；它们只作为失败证据，不进入正式包。

## 结论

本 BuildID 停止 Doorstop/BepInEx 路线。内容文本继续使用游戏原生 addon；UI 改为对精确当前 `Sunless.Game.dll` 生成静态差分和 standalone Harmony bootstrap。

## Unity 6 数据目录迁移

2026 版游戏使用 `~/Library/Application Support/com.failbettergames.sunlesssea/`，而不是旧版
`~/Library/Application Support/unity.Failbetter Games.Sunless Sea/`。如果菜单按钮已中文但开场故事、地点和正文仍英文，检查 addon 是否误装到了旧目录。`Player.log` 只出现
`Copying Json From Resources` 且运行时内容探针仍为英文时，表示 addon 未合并。正确放置后，事件
143942 的运行时标题应为“一名熟练的船员”。

不能以这些信号声称汉化已加载：

- 文件存在于游戏目录；
- `libdoorstop.dylib` 出现在进程内存；
- Preloader `Start()` 返回空异常；
- 游戏本身能启动。

完成证据必须包括 bootstrap/Harmony 日志和真实中文 UI。
