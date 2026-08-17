# macOS 静态 UI 汉化 PoC 执行交接

> 历史阶段记录：本文件保留最初 PoC 证据，其中 `IntroScript.PlayEAWarning`、旧数据目录和 HarmonyX 依赖结论已被后续实机验证推翻。正式 v6.0.5 以 `TitleScreenInit.Start`、Lib.Harmony 2.4.2 单文件运行时和 `com.failbettergames.sunlesssea` 为准，见 `04-package执行.md`。

## 结论

已在隔离 `build/macos-static/` 中完成一个不依赖 BepInEx 入口的 macOS 静态 UI 汉化 PoC。入口程序集由 tinygrox/SunlessSeaCN 源码 commit `e9bde736554913aa835f547f28e26ed6f393d515` 编译，并新增 `SSTranslator.Bootstrap.Init()`；Mono.Cecil patcher 将一次 `call Bootstrap.Init()` 注入当前 Steam BuildID 24437295 / Unity 6000.3.2f1 的 `Sunless.Game.dll` 中唯一的 `Sunless.Game.Scripts.UI.Intro.IntroScript.PlayEAWarning()`。

本阶段没有启动游戏、没有写入真实 `.app`、没有改存档、没有改 Windows 文件，也没有制作或提交正式安装器。PoC 证明了“standalone translation DLL + 0Harmony 及其 Managed 依赖闭包 + 资源 + 可校验的静态入口注入”可以隔离生成；真实游戏 UI 是否最终出现中文仍需主代理在 app clone 上用 bsdiff 和真实启动验收。

## 修改文件

- `macos-static/Bootstrap.cs`
  - 去掉 BepInEx attributes、`BaseUnityPlugin` 和 `Logger` 依赖。
  - `Bootstrap.Init()` 使用原子状态保证幂等；从程序集所在的 `Managed/` 显式定位 `Managed/SunlessSeaCN/Images` 与 `Managed/SunlessSeaCN/Data`，加载品质 JSON、替换启动图并执行 `Harmony.PatchAll`；异常写 `UnityEngine.Debug`。
- `macos-static/SunlessSeaChineseTranslation.csproj`
  - 复用 vendored tinygrox `Sources/**/*.cs`（排除 `PluginMain.cs`），以真实游戏 Managed 程序集和 BepInEx 5.4.23.5 的 `0Harmony.dll` 为编译引用。
- `macos-static/src/`
  - tinygrox 源码快照，来源 commit `e9bde736554913aa835f547f28e26ed6f393d515`。
- `macos-static/patcher/Program.cs`
  - 校验输入 SHA-256；要求唯一目标类型/方法和唯一 Bootstrap 签名；禁止原地覆盖；已注入输入可识别并幂等输出；重读输出并确认目标方法恰有一个 `Bootstrap.Init` 调用。
  - `--check-closure` 递归读取 `AssemblyRef`，要求非框架引用在目标 Managed 根可解析。
- `macos-static/patcher/SunlessSeaStaticPatcher.csproj`
- `scripts/build-macos-static-ui.sh`
- `tests/test_macos_static_ui.sh`

## 构建与测试

构建命令：

```text
./scripts/build-macos-static-ui.sh
bash tests/test_macos_static_ui.sh
```

构建结果：

- `dotnet restore/build`（dotnet 8）成功，插件和 patcher 均 0 warning / 0 error。
- 输入 `Sunless.Game.dll` SHA-256：`b7d5df522b8ae7c1ee4913b283586fc4d823f735159bf00753f42ce4a86474f0`，size `77392384`。
- 目标确认：`System.Void Sunless.Game.Scripts.UI.Intro.IntroScript::PlayEAWarning()`。
- 注入结果：`action=injected`。
- `bash tests/test_macos_static_ui.sh`：`PASS`；15 个图片、17 个 addon 文件；真实游戏 DLL hash 保持不变。
- `0Harmony.dll` 的递归 `AssemblyRef` 闭包：`closure-ok=0Harmony.dll`，实际必需文件为 `0Harmony.dll, Mono.Cecil.dll, MonoMod.RuntimeDetour.dll, MonoMod.Utils.dll`；六个 sidecar 均存在。
- 重复 patch 测试：`action=already-injected`，没有添加第二个调用。
- 输出程序集均为 PE32 Mono/.Net assembly；standalone DLL 的字符串中不含 `BepInEx` / `BaseUnityPlugin` / `PluginInfo`。

## 生成物与哈希

生成根目录：`build/macos-static/`。

- `staging/Managed/Sunless.Game.dll`
  - SHA-256 `f40ffd2e3c0c0ec6ae832b8e6d81198e1a48d90790596a7856a7f01ad3025e3d`
  - 仅 PoC 全量 patched DLL；正式分发不得直接携带它，应针对输入 hash 生成 bsdiff。
- `staging/Managed/Sunless.Game.original.dll`
  - 原始 hash `b7d5df522b8ae7c1ee4913b283586fc4d823f735159bf00753f42ce4a86474f0`，仅作为隔离对照。
- `staging/Managed/SunlessSeaChineseTranslation.dll`
  - SHA-256 `d7b68dd94f41cdaf32101ac1567a8f2fb476bdd293af2f18c1552b5d928e564c`。
- `staging/Managed/0Harmony.dll`
  - SHA-256 `1a21cc03424fc82c3dd1346905d16494536b9595ae4162228d99fb7c285c1031`。
- `staging/Managed/MonoMod.RuntimeDetour.dll`、`MonoMod.Utils.dll`、`Mono.Cecil.dll`
  - 运行时必需的 Harmony 依赖；闭包检查从 `0Harmony.dll` 递归解析到这三个程序集，均已复制到 Managed 根。
- `staging/Managed/Mono.Cecil.Mdb.dll`、`Mono.Cecil.Pdb.dll`、`Mono.Cecil.Rocks.dll`
  - 同版本 Cecil 侧载依赖，一并复制以避免 Unity Mono 后续符号/扩展加载缺失。
- `staging/Managed/SunlessSeaCN/Data/qualities.json`
  - SHA-256 `94fd39df2cc41e5cd711304909020924052833c26e418a102d33b9dd1a9845f3`。
- `patch-report.txt`
  - 包含原始输入 hash、目标方法、Bootstrap 方法、注入动作和输出 hash。
- `player-data/addon/Sunless_sea_CN_reborn/`
  - v6.0.4 macOS payload 中的 17 个翻译 JSON 文件。

## 临时装入 app 副本的精确映射

主代理在隔离 app clone 上验证时，目标 Managed 根是：

`Sunless Sea.app/Contents/Resources/Data/Managed/`

复制/应用顺序：

1. 对 clone 当前 `Managed/Sunless.Game.dll` 先校验 SHA-256 必须为 `b7d5df522b8ae7c1ee4913b283586fc4d823f735159bf00753f42ce4a86474f0`。
2. 对该文件应用本阶段输入对应的 bsdiff，输出仍命名为 `Managed/Sunless.Game.dll`；不要从仓库或 ZIP 分发完整 patched/original DLL。
3. 复制 `staging/Managed/SunlessSeaChineseTranslation.dll` 到 `Managed/SunlessSeaChineseTranslation.dll`。
4. 复制 `staging/Managed/0Harmony.dll` 及 `MonoMod.RuntimeDetour.dll`、`MonoMod.Utils.dll`、`Mono.Cecil*.dll` 到 `Managed/` 根。
5. 复制 `staging/Managed/SunlessSeaCN/Images/*.png` 到 `Managed/SunlessSeaCN/Images/`。
6. 复制 `staging/Managed/SunlessSeaCN/Data/qualities.json` 到 `Managed/SunlessSeaCN/Data/`。
7. 将 `player-data/addon/Sunless_sea_CN_reborn/` 复制到用户数据根 `/Users/tiny/Library/Application Support/unity.Failbetter Games.Sunless Sea/addon/Sunless_sea_CN_reborn/`；不得覆盖 saves。

`Bootstrap.Init()` 由 patched `PlayEAWarning()` 调用，不需要 BepInEx、Doorstop、Steam launch option 或 `.app/Contents` 内的 native loader。主代理仍须用实际 app clone 启动并观察 `Player.log`/窗口中文 UI；本阶段禁止我自行启动。

## 许可证风险

tinygrox 源仓库声明 GPL-3.0；本 PoC 复用了其 UI patch 源码，Standalone 入口和构建/patcher 也应保留 GPL-3.0 归属与源码提供义务。仓库已有 `THIRD-PARTY-NOTICES.md` 对该来源有说明，主代理打包时应补充本静态路线的归属说明。`0Harmony.dll` 使用 BepInEx 5.4.23.5 发行资产，继续按现有第三方声明处理。v6.0.4 翻译 JSON/图片的上游许可边界仍按仓库现有声明，不因本 PoC 改变。

## 剩余风险

- 尚未在 app clone 或真实游戏启动，不能宣称已观察到中文 UI。
- 静态注入会使 `Sunless.Game.dll` 随 Steam 更新失效；正式包必须绑定 BuildID/hash，并在安装器中拒绝不匹配版本。
- `0Harmony` 和 translation DLL 需由 Unity Mono 在 Managed 根解析；若当前 Unity 6 Mono 的程序集加载顺序不满足，需由真实启动日志确认。
- tinygrox patch 集合按其源码版本编译；若当前 BuildID 的类型/方法细节与源码假设存在差异，Harmony 可能在 `PatchAll` 时记录错误，需看 Player.log。
- 资源字体/中文 glyph 是否完整、存档中的旧 addon 合并行为、Steam 云同步覆盖策略尚未在本阶段验证。

## 经验候选

- 症状：原 macOS 插件依赖 BepInEx 进程入口，实际进程过滤器为 `.exe`，且 loader 链路未产生日志。
- 证据：当前 macOS 进程实际为 `Sunless Sea`；当前 `Sunless.Game.dll` 含唯一 `Sunless.Game.Scripts.UI.Intro.IntroScript.PlayEAWarning()`；静态测试对 patched 输出重读并确认恰一个 `Bootstrap.Init` 调用。
- 已验证根因：BepInEx 入口不是静态 UI patch 必需条件；可把初始化调用放到游戏启动脚本方法中以避开进程名过滤，但不等于真实 UI 已验收。
- 可复用修复：以当前输入 SHA 绑定 Mono.Cecil patcher；入口幂等；资源路径固定在 `Managed/SunlessSeaCN`；正式分发使用 bsdiff，不携带完整游戏 DLL。
- 验证结果：dotnet build 0 warning/0 error、patcher 注入与重复注入测试通过、真实输入 hash 未改变；未启动游戏。
- 适用范围：本机 Steam BuildID 24437295 / Unity 6000.3.2f1 / Mono 程序集。
- 反例：不能推断其他 BuildID、arm64 原生 runtime、BepInEx loader 或真实中文 UI 均已兼容；不能把 PoC 全量 patched DLL 直接当发布包。
- 建议落点：项目阶段交接与 macOS 构建/安装器的版本门禁；不要晋升为通用 Unity loader 规则。
