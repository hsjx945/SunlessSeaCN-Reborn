# x86_64 nlist_64 interpose 执行交接

## 结论

本次完成仅用于诊断的 x86_64 DYLD_INTERPOSE 原函数解析替换：wrapper 首次调用早期遍历当前 dyld image，按 SUNLESS_SEA_MONO_LIBRARY_PATH 的 realpath 精确选中游戏 Mono Mach-O，解析内存中的 LC_SEGMENT_64、LC_SYMTAB 与 nlist_64，以 slide + n_value 得到原函数地址，不再从句柄取得 mono_jit_init_version。

先前诊断确认缺少 System.Native；本次按同一根因做最后一次局部修复：从 RTLD_DEFAULT 解析 mono_dllmap_insert，将 System.Native 映射到游戏自带的绝对 libmono-native.dylib，并进行唯一一次 20 秒 Rosetta 实机诊断。

最终 20 秒诊断证明：

- wrapper 命中；
- 目标 Mono image/path、slide、_mono_jit_init_version 的 N_SECT|N_EXT 符号、n_value=0x62988、运行地址和 __TEXT,__text / __LINKEDIT bounds 均被记录；
- 原始 mono_jit_init_version 成功调用并返回 Mono root domain；
- BepInEx.Preloader.dll 成功加载并找到 Doorstop.Entrypoint.Start()；
- Mono dllmap 注册成功，Start() 返回 exception=null；但没有 BepInEx LogOutput.log、插件/Harmony 或中文 UI 证据。

按任务包失败边界，本阶段到此收口，不继续扩展异常对象解码、二次注入或其他 loader 方案；不能把 macOS 汉化称为已完成。

## 修改范围

- native/macos/sunlesssea_mono_interpose.c
  - 增加 _dyld_image_count / _dyld_get_image_name / _dyld_get_image_header / _dyld_get_image_vmaddr_slide 遍历。
  - 两端路径先 realpath 后比较，只接受目标 x86_64 image。
  - 严格检查 Mach-O header/load-command/cmdsize/ncmds、segment/section 边界、唯一 __LINKEDIT、唯一 LC_SYMTAB、symbol/string 文件及运行时 bounds。
  - 只接受唯一 _mono_jit_init_version 且同时满足 N_SECT|N_EXT 的 nlist_64，确认地址位于可执行 __TEXT,__text 且不等于 wrapper。
  - 解析尝试和地址缓存均为一次；之后直接调用缓存原函数，再同步执行一次 Preloader。
  - Preloader 调用前从 RTLD_DEFAULT 解析 mono_dllmap_insert，以 assembly=NULL、func/tfunc=NULL 注册 System.Native 到绝对游戏 libmono-native.dylib；不调用 mono_set_dirs。
- tests/test_macos_interpose_artifact.sh：检查 dyld/nlist/Mach-O 解析路径，并拒绝旧句柄解析、RTLD_NEXT、RTLD_NOLOAD、Doorstop/fishhook/flat namespace 文本。
- scripts/build-macos-interpose.sh：保持 x86_64、C11、-Wall -Wextra -Werror、ad-hoc codesign 构建门禁。
- scripts/run-macos-interpose-diagnostic.sh：保持 staging-only BepInEx/插件、插件进程名等长修补、x86_64 单次诊断、真实存档 hash/size/mtime 与进程清理；为 staging core/Managed 设置 MONO_PATH，并传入并校验游戏绝对 regular libmono-native.dylib。

未修改游戏 .app/Contents、翻译 JSON/图片、用户存档、Windows 包或正式安装包；未提交 Git。

## 静态验证

命令：

    bash -n scripts/build-macos-interpose.sh scripts/run-macos-interpose-diagnostic.sh tests/test_macos_interpose_artifact.sh
    scripts/build-macos-interpose.sh
    tests/test_macos_interpose_artifact.sh

结果：全部通过。产物为 x86_64 Mach-O，ad-hoc 签名通过，依赖检查仅接受系统库，含 __DATA,__interpose；静态检查确认 nlist 路径并拒绝旧解析路径。

最终产物 SHA-256：

    32ea3d7529df53a83bb9676618efe2ef1fa10a057632f7510131909dc9eb59b

## 唯一实机运行

命令：

    SUNLESS_SEA_INTERPOSE_WAIT_SECONDS=20 scripts/run-macos-interpose-diagnostic.sh

证据目录：

    /var/folders/gn/tdsg5xj97t12l1mmvsvnw6rc0000gn/T//sunlesssea-mono-interpose.8hb2t7

关键 interpose 日志：

    wrapper-enter root-domain=Unity Root Domain runtime=v4.0.30319
    nlist-image index=0 path=/Users/tiny/Library/Application Support/Steam/steamapps/common/SunlessSea/Sunless Sea.app/Contents/Frameworks/libmonobdwgc-2.0.dylib header=0x108f89000 slide=4445474816 symbol=_mono_jit_init_version address=0x108feb988 text-bounds=[0x108f899b0,0x1091eac10) linkedit-bounds=[0x1094d5000,0x10950d000)
    nlist-symbol name=_mono_jit_init_version index=1189 type=0xf n_value=0x62988 address=0x108feb988 bounds=[0x108f899b0,0x1091eac10)
    wrapper-original-resolve source=nlist64 result=ok image=/Users/tiny/Library/Application Support/Steam/steamapps/common/SunlessSea/Sunless Sea.app/Contents/Frameworks/libmonobdwgc-2.0.dylib address=0x108feb988
    wrapper-original result=ok domain=0x11f42dd20
    bootstrap-start result=once domain=0x11f42dd20
    mono-api result=ready source=RTLD_DEFAULT
    mono-domain root=0x11f42dd20 wrapper-domain=0x11f42dd20
    mono-thread-attach result=ok thread=0x11f438f60
    path-check label=mono-native-library path=/Users/tiny/Library/Application Support/Steam/steamapps/common/SunlessSea/Sunless Sea.app/Contents/Frameworks/libmono-native.dylib result=ok size=1665808
    mono-dllmap result=ok assembly=null dll=System.Native target=/Users/tiny/Library/Application Support/Steam/steamapps/common/SunlessSea/Sunless Sea.app/Contents/Frameworks/libmono-native.dylib func=null tfunc=null
    assembly-open result=ok path=/var/folders/gn/tdsg5xj97t12l1mmvsvnw6rc0000gn/T//sunlesssea-mono-interpose.8hb2t7/BepInEx/core/BepInEx.Preloader.dll image-name=BepInEx.Preloader
    entrypoint-method name=Start value=0x7f9266a35c28 method-name=Start
    entrypoint-signature value=0x7f9266a35c50 param-count=0
    entrypoint-invoke result=ok return=0x0 exception=null
    bootstrap-finish result=ok

这说明 nlist 原函数链路和 Preloader 调用已经打通，System.Native dllmap 注册成功且 Start() 返回 exception=null；但 BepInEx LogOutput.log 仍不存在/为空，插件/Harmony 与中文 UI 均未加载/观察到。runner 退出码为 1，失败仅来自插件/Harmony/UI 验收门禁。

## 存档与进程

真实路径：

    /Users/tiny/Library/Application Support/unity.Failbetter Games.Sunless Sea/saves/Autosave.json
    /Users/tiny/Library/Application Support/unity.Failbetter Games.Sunless Sea/saves/steam_autocloud.vdf

两份存档在运行前后均保持不变：

    Autosave.json sha256=5700a5888e4327bc1bd4e3df0acb23ce4aac751e5b3dae581a7bd06b18a4b181 size=73560 mtime=1511581889
    steam_autocloud.vdf sha256=dd2ca71bd6a035cef54dcb2e9d8e50daf8e112f7643df5b7bd4946a8ffe88476 size=52 mtime=1786974984
    save-check=unchanged
    process-check=no Sunless Sea process remains

## 风险与未完成

- nlist 解析已在实际目标 image 上成功，不再是当前阻塞点。
- System.Native dllmap 已生效，Doorstop.Entrypoint.Start() 返回 exception=null；但没有 BepInEx 日志、插件/Harmony 或中文 UI 证据，不能进入正式包。
- 本 interpose dylib 仅为诊断产物，不能进入正式 macOS 安装包。

## 经验候选

- 症状：旧句柄解析在 DYLD_INTERPOSE 下只得到 wrapper；替换为 dyld image 内存 Mach-O 的 nlist 解析后，原 Mono 函数可被准确调用。
- 证据：目标 image realpath 命中；N_SECT|N_EXT 唯一符号 n_value=0x62988，运行地址位于 __TEXT,__text，随后 wrapper-original result=ok 并返回 root domain。
- 可复用边界：在 macOS interpose 诊断中，原符号解析必须约束 image、架构、load-command/string bounds 和可执行地址范围；仅凭 dlsym 句柄结果不可证明得到原函数。
- 当前反例：原函数、Mono domain、System.Native 映射和 Preloader Start() 已成功，但 BepInEx 日志/插件/Harmony/UI 仍未出现，所以这条路径不能直接转为正式 loader。
