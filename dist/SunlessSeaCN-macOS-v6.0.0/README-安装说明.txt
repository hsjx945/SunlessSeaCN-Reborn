Sunless Sea 中文补丁 6.0.0 - macOS

安装：将本文件夹放在本地磁盘，双击 Install-SunlessSeaCN.command。脚本会寻找 Steam 的 Sunless Sea.app，并同时探测新版和旧版 Unity 数据目录。

首次运行若 macOS 阻止脚本：右键脚本选择“打开”，或在终端执行 chmod u+x *.command *.sh 后再运行。必要时只对游戏目录执行：
  xattr -dr com.apple.quarantine "$HOME/Library/Application Support/Steam/steamapps/common/SunlessSea"

卸载：双击 Uninstall-SunlessSeaCN.command。安装器会在覆盖已有文件前创建备份。

注意：本包使用 BepInEx 5.4.23.5 macOS universal loader；Windows 可在本机完整测试，macOS 运行时仍需在 Mac 上第一次启动验证。
