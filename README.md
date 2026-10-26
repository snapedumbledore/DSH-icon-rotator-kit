DSH-icon-rotator-kit —— DeepSeek Harness 

适用：Windows 10 / 11，已安装 DeepSeek Harness，普通用户账号（无需管理员）。

部分二次元形象来自https://space.bilibili.com/4168597   ZipZipPipe

<img width="200" height="200" alt="C02_DeepSeek_fullbody" src="https://github.com/user-attachments/assets/4b03a8af-a2b9-4b08-a641-1a4056f58dbb" />
<img width="200" height="200" alt="C04_Qwen_fullbody" src="https://github.com/user-attachments/assets/b6237aac-414d-41f9-afe0-dcb8f4a1a84d" />
<img width="200" height="200" alt="C08_Mistral_fullbody" src="https://github.com/user-attachments/assets/a7debc7d-ed62-4e0d-bcd8-e8c016391663" />

安装（每台电脑、每个 Windows 用户只需一次）

  1. 把整个 DSH-icon-rotator-kit 文件夹拷到目标电脑。
  2. 双击 install.cmd。
  3. 完全退出 DeepSeek Harness（托盘图标右键 → 退出），再重新打开。

切换时机（v5）

  * 只在“软件退出”时换图：进程全部消失后立刻换（实测 60~100 毫秒），
    快捷方式图标同步更换。
  * 启动时不会换图：打开的永远是上次退出时换好的那一张。
  * 唯一例外：如果状态文件显示上次应用还在运行（掉电 / 被强杀，没来得及
    执行退出轮换），守护下次启动时会补换一次，只在真正异常时触发。

注意：关闭窗口 ≠ 退出软件

  点窗口右上角 X 只是隐藏到托盘，进程仍在运行；此时再点快捷方式只会聚焦
  已有窗口（单实例），托盘图标不会变。要触发切换必须真正退出：
  托盘图标右键 → 退出（或在任务管理器结束 DeepSeek Harness.exe）。

出问题时先跑诊断

  powershell -NoProfile -ExecutionPolicy Bypass -File ".\diagnose.ps1"

  它会打印：安装路径、当前 tray.ico 对应哪一款、自启项、守护进程（含父进程）、
  三个快捷方式的图标、guard.log / rotate.log 尾部、以及当前 DSH 进程的启动时间。
  常见结论：
    * guard process = NOT RUNNING           → 守护没起来（杀软/策略拦截），重跑 install.cmd
    * 日志里只有 guard started，没有 exit 行 → 说明软件从未真正退出（见上）
    * 日志里有 rotated -> xxx (exit)        → 切换已生效，看下一条启动时间是否晚于它

安装做了什么（全部在用户目录，可完整还原）

  %LOCALAPPDATA%\DSH-icon-rotator\
    icons\spring|summer|autumn|winter.ico   四款图标
    rotate.ps1                              手动轮换 / 指定季节 / 恢复
    guard.vbs                               后台守护（内置毫秒级换图，不依赖 PowerShell）
    original-tray.ico                       首次安装时备份的原始图标
    install-path.txt                        记录应用安装目录
    lnk-backup\                             三个快捷方式改动前的备份
    state.json / rotate.log / guard.log     状态与日志
    diagnose.ps1                            排错脚本
  HKCU\Software\Microsoft\Windows\CurrentVersion\Run
    DSH-icon-rotator = wscript.exe //nologo "...\guard.vbs"
  三个快捷方式：只修改 IconLocation，统一指向安装目录里的
  <安装目录>\resources\DSH-icon-chain\<图标名>.ico（与托盘同一条图标链路）。
  TargetPath / Arguments / AUMID 保持不变。

统一图标链路（v6，重要）

  托盘、桌面快捷方式、开始菜单快捷方式、任务栏固定项现在只使用安装目录里的图标：

      <安装目录>\resources\tray.ico                     ← 托盘读取
      <安装目录>\resources\DSH-icon-chain\<图标名>.ico   ← 三个快捷方式（同一张图的副本）

  轮换时：选中的图标先复制成 tray.ico，再复制成 DSH-icon-chain\<图标名>.ico，
  然后重新保存三个快捷方式。快捷方式的 IconLocation 不再指向图标库或 kit 目录。

  为什么快捷方式要单独放一份副本：Windows 的 shell 图标缓存按“路径”缓存。
  如果快捷方式始终指向 tray.ico 这个固定路径、而文件内容每次轮换都变，
  Explorer 会一直显示缓存里的旧图（实测过：换图后快捷方式仍显示上一张）。
  用“每个图标一个文件名”的副本，路径随图标变化，缓存永远不会过期。

  为什么不能指向图标库：本套件常被放在 DSH 的沙箱工作区
  （default-workspace）里，该目录下的文件带 Low 完整性标签，Windows
  资源管理器解析快捷方式图标时会拒绝加载这类文件，显示成空白页图标；
  而托盘是应用自己直接读文件，所以看起来“托盘正常、快捷方式空白”。
  把图标统一到安装目录（Medium 完整性）即可彻底避开。

常用命令（PowerShell）

  # 立即随机换一张
  & "$env:LOCALAPPDATA\DSH-icon-rotator\rotate.ps1"

  # 指定季节（spring / summer / autumn / winter）
  & "$env:LOCALAPPDATA\DSH-icon-rotator\rotate.ps1" -Season winter

  # 恢复原始图标（守护仍在，下次退出照常轮换）
  & "$env:LOCALAPPDATA\DSH-icon-rotator\rotate.ps1" -Season restore

  # 完全卸载并还原
  & "$env:LOCALAPPDATA\DSH-icon-rotator\uninstall.ps1"

自定义安装目录：install.ps1 -InstallDir "D:\Apps\DeepSeek Harness"
双击被安全软件拦截：右键 → 以 PowerShell 运行；或属性 → 解除锁定。
若提示「禁止运行脚本」：powershell -NoProfile -ExecutionPolicy Bypass -File <脚本路径>

应用更新会整包替换安装目录，tray.ico 与快捷方式图标可能被重置，
下次退出/登录时守护会自动重设，无需处理。
增加 / 更换图标（v7）

  图标库只有一个扫描目录（每次换图时实时扫描）：

      %LOCALAPPDATA%\DSH-icon-rotator\icons\*.ico

  install.cmd 会把 kit 的 icons\ 全量复制到这里；应用自带的
  resources\DSH-season-icons 与 kit 目录本身不再被扫描。

  两种新增方式，任选其一：
    A. 直接把 .ico 复制到上面这个目录，下次退出 DSH 即生效（无需重装）。
    B. 把 .ico 放进 kit 目录的 icons\ 子文件夹，然后重新双击 install.cmd，
       安装器会把它全部复制进该目录。

  规则：
    * 文件名不要包含 original / backup（会被忽略）
    * 必须是真正的 ICO 文件（文件头 00 00 01 00），建议含 16~256 像素图层
    * 内容完全相同的重复图标按文件大小去重
    * 非法文件会被跳过，并在 rotate.log 记录 WARN not a valid ico
  查看识别结果：
    & "$env:LOCALAPPDATA\DSH-icon-rotator\rotate.ps1" -List
  它会打印 sources（唯一扫描目录）与 library（实际可用的图标）。

  建议把 kit 文件夹放在桌面或文档里，不要放在应用安装目录内——
  应用更新会整包替换安装目录，可能把 kit 一起删掉。
