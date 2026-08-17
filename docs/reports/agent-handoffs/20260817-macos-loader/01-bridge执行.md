# x86_64 Mono bridge 执行交接

## 结论

诊断 bridge 已构建并在真实 Steam Sunless Sea 进程中成功执行到 `Doorstop.Entrypoint.Start()`：Mono API 从 `RTLD_DEFAULT` 解析成功，root domain 获取成功，Preloader 程序集/`Doorstop.Entrypoint.Start()`/零参数签名均找到，`mono_runtime_invoke` 返回 `exception=0x0`。

但本次真实启动未生成 staging 的 `BepInEx/LogOutput.log`，也没有可交接的 BepInEx chainloader 或中文插件日志；因此 bridge 只证明了“绕过 Doorstop 可以把 Preloader 程序集调用起来”，没有证明 BepInEx 完成初始化，更没有证明中文 UI。按任务包失败边界，本执行代理不扩张到 interpose/fishhook 或修改游戏本体。

## 允许范围内的改动

- `native/macos/sunlesssea_mono_bridge.c`
  - constructor 仅初始化路径/日志、原子 once 状态并启动一个 detached pthread；Mono `dlsym`、root-domain 轮询和托管调用全部在后台线程。
  - 从 `RTLD_DEFAULT` 解析 Mono embedding API；最多 30 秒轮询 root domain，然后 `mono_thread_attach`。
  - 检查绝对 Preloader 路径和 Managed 目录；文件使用 `O_NOFOLLOW|O_CLOEXEC`，日志失败回退 stderr。
  - 设置 `DOORSTOP_PROCESS_PATH`、`DOORSTOP_MANAGED_FOLDER_DIR`、`DOORSTOP_INVOKE_DLL_PATH`、`DOORSTOP_DLL_SEARCH_DIRS`。
  - 通过 `mono_domain_assembly_open`、image/class/method/signature 检查和一次 `mono_runtime_invoke` 调用 `Doorstop.Entrypoint.Start()`；只记录 exception 指针，不调用托管 ToString。
- `scripts/build-macos-bridge.sh`
  - x86_64、`-Wall -Wextra -Werror`、系统 SDK、ad-hoc codesign 构建。
- `scripts/run-macos-bridge-diagnostic.sh`
  - 临时 staging BepInEx/插件，插件中的 `Sunless Sea.exe` 等长字节串只在 staging 中补成等长 `Sunless Sea`，只通过 `DYLD_INSERT_LIBRARIES` 注入 bridge，`arch -x86_64` 启动真实 app；保存启动前后存档 hash/size/mtime。
- `tests/test_macos_bridge_artifact.sh`
  - 校验 x86_64、签名、仅系统依赖和禁止 Doorstop/interpose 关键词。

未修改 build_packages.py、dist、Windows、翻译 JSON/图片、`.app/Contents`、用户存档或 Git。

## 构建与静态验证

命令：

```text
scripts/build-macos-bridge.sh
tests/test_macos_bridge_artifact.sh
```

结果：通过。产物：`build/macos-bridge/sunlesssea_mono_bridge.dylib`；`file` 显示 `Mach-O 64-bit dynamically linked shared library x86_64`；ad-hoc `codesign --verify` 通过；`otool -L` 仅显示 `/usr/lib/libSystem.B.dylib`。本次构建 SHA-256：

```text
6065e63f4f9d54b994209cea9b473887dbabf28ecad85c3526b1d8eb08435d16
```

## 一次真实运行证据

命令：

```text
scripts/run-macos-bridge-diagnostic.sh
```

运行环境：真实游戏路径 `/Users/tiny/Library/Application Support/Steam/steamapps/common/SunlessSea/Sunless Sea.app/Contents/MacOS/Sunless Sea`；强制 `arch -x86_64`；临时 staging：

```text
/var/folders/gn/tdsg5xj97t12l1mmvsvnw6rc0000gn/T//sunlesssea-mono-bridge.gmCDzl
```

bridge 日志关键行：

```text
mono-api result=not-ready source=RTLD_DEFAULT
mono-domain root=0x111f52d20 attempt=4
mono-thread-attach result=ok thread=0x111f5de40
path-check label=preloader ... result=ok size=43008
path-check label=managed ... result=ok
assembly-open result=ok ... image-name=BepInEx.Preloader
entrypoint-class namespace=Doorstop name=Entrypoint value=0x7fa128a16298
entrypoint-method name=Start value=0x7fa128a16408 method-name=Start
entrypoint-signature value=0x7fa128a16430 param-count=0
entrypoint-invoke result=ok return=0x0 exception=0x0
```

目标 staging `BepInEx/LogOutput.log` 不存在，故没有 chainloader、插件加载或 Harmony 证据。游戏进程在 bridge 调用后保持运行至诊断结束并由 runner 清理；当前无残留 `Sunless Sea` 测试进程。Player.log 只确认 Unity 6.0.3.2f1/Mono 正常初始化，未出现 BepInEx 文本。

## UI 与存档

- 本次执行代理未作窗口截图/中文 UI 验收；中文 UI 结论留给后续 verifier。
- runner 对 `/Users/tiny/Library/Application Support/unity.Failbetter Games.Sunless Sea/Autosave.json` 和 `steam_autocloud.vdf` 均记录为启动前后 missing；没有改写或创建用户存档。
- 临时 staging 使用 v6.0.1 本地 BepInEx payload 作为任务包允许的诊断 fallback；v6.0.4 payload 可通过 `SUNLESS_SEA_CN_MAC_PAYLOAD_GAME` 显式传入。v6.0.1 仅用于临时 staging，不进入正式包。

## 风险与未完成

- `Entrypoint.Start()` 正常返回并不等于 BepInEx chainloader 初始化；当前缺失 LogOutput 说明仍有下一层运行时问题，可能与 Preloader 的文件/运行时路径或其内部启动条件有关。
- 不可据此把 bridge 放进正式 macOS 安装包；正式包仍需在后续 verifier 阶段证明 BepInEx 日志、插件/Harmony 和真实中文 UI。
- 不得在本执行代理内扩张为 interpose/fishhook、重复注入 Doorstop、修改游戏本体或改动翻译资源。

## 经验候选

- 症状：Doorstop 不产日志时，bridge 可在无 Doorstop 注入的情况下解析 Mono 并调用 `Doorstop.Entrypoint.Start()`。
- 原始证据：真实 x86_64 运行日志中 `assembly-open result=ok`、`param-count=0`、`entrypoint-invoke result=ok ... exception=0x0`。
- 已验证根因：仅能确认原 Doorstop 路径问题之外，Preloader 内部初始化仍未产生日志；具体失败点尚未确认。
- 可复用修复：将 bridge 作为一次性、30 秒、绝对路径、带路径检查的诊断工具；不要将这次 bridge 结论升级为正式 loader 方案。
- 验证结果：bridge 运行不崩溃，BepInEx/插件/UI 尚未验证。
- 适用范围：本机 Sunless Sea Unity Mono x86_64 诊断。
- 反例：不能推断 arm64 原生路径、正式包兼容性或 BepInEx 已加载。
- 建议落点：保留在本阶段交接记录，不晋升为全局规则或正式安装器行为。

未提交 Git；按任务包要求由主代理决定后续 verifier/收口。
