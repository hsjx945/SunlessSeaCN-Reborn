Sunless Sea 中文补丁 6.0.1 - macOS

安装包可以放在下载文件夹、桌面或其他本地目录，不需要把整个安装包文件夹放进游戏目录。解压后双击 Install-SunlessSeaCN.command；脚本会寻找包含 Sunless Sea.app 的 Steam 游戏根目录。

游戏根目录是：
  ~/Library/Application Support/Steam/steamapps/common/SunlessSea/
其中应当能看到 Sunless Sea.app。安装器会把 payload/game 的内容复制到这个目录，把 payload/data 的文本 addon 复制到玩家数据目录。不要把文件复制到 Sunless Sea.app/Contents。

如果 Finder 报“无法运行，因为你没有正确的访问权限”，在终端执行（把路径改成解压后的实际路径）：
  cd "/path/to/SunlessSeaCN-macOS-v6.0.1"
  chmod u+x Install-SunlessSeaCN.command Install-SunlessSeaCN.sh Uninstall-SunlessSeaCN.command Uninstall-SunlessSeaCN.sh
  xattr -dr com.apple.quarantine .
  ./Install-SunlessSeaCN.command
也可以直接绕过执行位运行：
  bash Install-SunlessSeaCN.sh

安装后，在 Steam 的 Sunless Sea“属性 → 通用 → 启动选项”中设置：
  ./run_bepinex.sh %command%
这样 Steam 才会通过 BepInEx 启动游戏。

卸载：双击 Uninstall-SunlessSeaCN.command，或在终端运行 bash Uninstall-SunlessSeaCN.sh。安装器会在覆盖已有文件前创建备份。

注意：本包使用 BepInEx 5.4.23.5 macOS universal loader；Windows 可在本机完整测试，macOS 运行时仍需在 Mac 上第一次启动验证。
