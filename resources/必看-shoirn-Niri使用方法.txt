
【可以查阅的文档】
ArchWiki: https://wiki.archlinux.org/title/Main_page
NiriWiki: https://github.com/niri-wm/niri/wiki
ShorinArch: https://shorin.xyz/wiki
Shorin一键配置脚本: https://shorin.xyz/wiki/archsetup

【重要工具】
shorinniri命令可以对shorinniri桌面进行初始化、更新、卸载等操作。详情看shorinniri命令的帮助信息。


【重要按键】
super+shift+/ 打开按键教程
super+T 打开终端
super+E 打开文档管理器
super+Z 开始菜单
super+Q 关闭窗口
super+R 按预设切换 宽度
super+F 最大化
super+H/L 左右切换聚焦
Super+alt+F 全屏
super+alt+V 开关剪贴板
super+alt+A 截图
super+右键 调整窗口大小
super+左键 移动窗口
super+V 切换浮动窗口
super+F10 随机更换壁纸（壁纸存放在~/Pictures/Wallpapers目录）
super+shift+F10 下载随机动漫壁纸
详细的按键注释看~/.config/niri里的.kdl文件。


如果出现网络问题可以进行以下操作更换wifi后端：
sudo rm /etc/NetworkManager/conf.d/iwd.conf
sudo systemctl restart NetworkManager

【输入法】
super+空格切换输入法。第一次使用输入法有可能无法使用，重启一下输入法可以解决。
f4可以打开菜单。如果出现卡A的情况可以试试按右shift解决。
使用fcitx5配置可以对输入法进行细节配置

【实用命令】
pac 安装软件 (安装软件还可以用bazaar，这是flatpak软件商城)
pacr 卸载软件
mirror-update 更新镜像源
sysup 更新系统
clean 系统清理
quicksave 快速存档
运行shorin命令可以看到所有可用的便利命令

【Ai助手】
如果你没有跳过常用软件安装步骤的话，会安装一个叫作opencode的开源ai助手，有免费模型可以用，你有api的话也可以自己导入。如果你有查找文件之类的需求直接询问这个Ai助手会很方便。想修改配置的话请谨慎辨别ai信息是否准确，谨慎使用ai修改文件。不喜欢的话可以删除：pacr opencode


【有趣实用的TUI软件（基于终端的用户交互程序）】
命令：作用
gdu：磁盘空间管理
nmtui：网络配置工具
impala：wifi连接工具，tab键切换，上下左右选择，回车确认（需要iwd后端）
btop：任务管理器
yazi：文档管理器
fastfetch：系统信息显示工具
更多软件信息可以看一键配置脚本的文档。

【如果不想要了或者安装失败了可以回档】
/usr/local/bin下有两个脚本可以用来回档到运行脚本之前的状态。
回到安装桌面前：shorin-de-undochange
回到运行脚本前：shorin-undochange

【关于系统维护】
1. 系统更新
请一定使用sysup命令更新系统，不要直接pacman -Syu。更新时要注意是否有重要新闻，sysup命令会在更新前自动创建quicksave-sysup快照，如果更新后出现问题可以从任意快照启动项进入系统运行quickload命令回档。

2. 系统清理
clean命令可以清理软件包缓存、回收站、截图、录屏、超数量上限的快照、btrfs备份子卷等内容。clean all命令可以更进一步，清理所有软件包缓存和所有快照。home目录下的.cache文件内的文件也都是可以安全删除的缓存，不过一股脑删除可能会少用户登录什么的，可以使用gdu寻找大文件删除。

3. 快速存档
活用btrfs快照存档，我的quicksave命令可以快速创建描述为quicksave的快照，做不了解的事情记得先快速存档（Mod+F5），我设置了合理的快照数量限制，不用担心快照占用磁盘空间，放心存。

