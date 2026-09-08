# Shorin KDE 使用方法

## 可以查阅的文档

- ArchWiki: <https://wiki.archlinux.org/title/Main_page>
- KDE 用户文档: <https://userbase.kde.org/Welcome_to_KDE_UserBase>
- ShorinArch: <https://shorin.xyz/wiki>
- Shorin 一键配置脚本: <https://shorin.xyz/wiki/archsetup>

## AI 助手

### Miyu

<https://github.com/SHORiN-KiWATA/Miyu>

Miyu 是我做的 AI 助手，已集成进终端，终端打字直接无缝对话。

- 运行 `miyu normal` 进入普通模式的 TUI
- 运行 `miyu dev` 进入开发模式的 TUI
- 运行 `miyu config` 进行自定义配置，支持自定义提示词、供应商、模型

如果有查找文件、安装软件、系统异常、查询系统信息之类的需求，可以直接询问这个 AI 助手，例如「我的快捷键配置文件在哪里？」「我要怎么安装软件」「帮我安装 steam」「我的 steam 没法用输入法」，其他问题当然也可以。

默认使用的模型是 opencodezen 的公共密钥，但是他们砍了公共密钥的额度，所以对话几次就没额度了，建议配一个自己的，可以去 opencode 的官网注册一个 opencodezen 的账号用它们的免费额度。

#### 卸载

想移除 Miyu 的话运行下面的命令：

```bash
# 先移除和终端的集成
miyu remove-shell-hook

# 然后删除包
yay -Rns miyu
```

## 重要按键

快捷键的设置路径：系统设置 > 输入和输出 > 键盘 > 快捷键

### 应用程序

| 按键 | 作用 |
|---|---|
| `Meta+Z` | KRunner（搜索/启动） |
| `Alt`（单独按下） | 应用程序启动器（菜单） |
| `Meta+T` | 终端（Konsole） |
| `Meta+B` | 浏览器 |

### 窗口管理

| 按键 | 作用 |
|---|---|
| `Meta+Q` | 关闭窗口 |
| `Meta+Ctrl+Q` | 强制终止窗口 |
| `Meta+F` | 最大化窗口 |
| `Meta+H` | 最小化窗口 |
| `Meta+Alt+F` | 全屏显示 |
| `Meta+C` | 移动窗口到中央 |
| `Meta+M` | 暂时显示桌面 |
| `Meta+左键` | 移动窗口 |
| `Meta+右键` | 调整窗口大小 |

### 磁贴窗口管理

| 按键 | 作用 |
|---|---|
| `Meta+F9` | 磁贴编辑模式开关 |
| `Meta+W` / `A` / `S` / `D` | 快速铺放（上下左右） |

> 提示：按下 `Meta+F9` 后可以编辑自己喜欢的平铺布局。

### 工作空间

| 按键 | 作用 |
|---|---|
| `Meta`（单独按下） | 显示/隐藏桌面总览 |
| `Meta+Tab` | 切换活动 |
| `Meta+Alt+滚轮` | 切换工作区 |
| `Meta+Ctrl+滚轮` | 缩放屏幕 |

## 输入法

- `Meta+空格` 或者 `Ctrl+空格` 切换输入法。第一次使用输入法有可能无法使用，重启一下输入法可以解决。
- 切换为中文后输入时按下 `F4` 可以打开菜单。如果出现卡 A 的情况可以试试按右 `Shift` 解决。
- 使用 `fcitx5-configtool` 命令可以对输入法进行细节配置。
- 如果输入法出现异常，看这个页面：<https://github.com/SHORiN-KiWATA/Shorin-ArchLinux-Guide/wiki/%E4%B8%AD%E6%96%87%E8%BE%93%E5%85%A5%E6%B3%95>，通常能解决问题，如果无法解决可以在交流群询问。

## 外观配置

- Konsole 终端右键的设置菜单里可以对工具栏显示、外观之类的进行配置。
- 如果你不喜欢我的 KDE 外观配置，可以在设置中心的主题部分进行更改。
- 如果你想要调整圆角，可以找到设置里的窗口管理 > 桌面特效部分修改 rounded corner（大概是这个名，新版本有点 bug 所以可能已经移除了这个）。

## 安装和卸载软件

- `pac` 命令安装软件。
- `pacr` 命令卸载软件。

## 实用命令

| 命令 | 作用 |
|---|---|
| `mirror-update` | 更新镜像源 |
| `sysup` | 更新系统 |
| `clean` | 系统清理 |
| `quicksave` | 快速存档 |
| `quickload` | 快速读档 |

运行 `shorin` 命令可以看到所有可用的便利命令。

## 有趣实用的 TUI 软件

TUI 即基于终端的用户交互程序。

| 命令 | 作用 |
|---|---|
| `gdu` | 磁盘空间管理 |
| `btop` | 任务管理器 |
| `yazi` | 文档管理器 |
| `fastfetch` | 系统信息显示工具 |

在 fish 终端里用 `y` 命令代替 `yazi` 启动，退出时终端会自动切换到你在 yazi 里最后停留的目录。

更多软件信息可以看一键配置脚本的文档。

## 运行 Windows 软件

<https://github.com/SHORiN-KiWATA/proton-wrapper>

此功能由 `shorin-proton-wrapper-git` AUR 包提供。双击 `.exe` 文件会自动用「运行 Windows 软件」打开，会自动使用 DW-Proton 在 `~/.proton` 目录初始化运行环境。

如果用「设置 Windows 软件运行环境」打开的话可以进行各种自定义设置，如运行器、MangoHud 屏显（帧数、硬件占用之类的）、GameScope（如果遇到窗口异常、交互异常的话可以尝试用 GameScope 打开）等。

如果 DW-Proton 无法运行软件，可以试试用 GE-Proton；如果连 GE-Proton 也不行，别的大概率也不行，建议从环境变量、运行参数入手解决问题，或者尝试兼容层以外的运行方案。

## 如果不想要了或者安装失败了可以回档

如果你是用我的 shorin-arch-setup 脚本安装的，`/usr/local/bin` 下有两个脚本可以用来回档到运行脚本之前的状态：

- 回到安装桌面前：`shorin-de-undochange`
- 回到运行脚本前：`shorin-undochange`

## 关于系统维护

### 1. 系统更新

请一定使用 `sysup` 命令更新系统，不要直接 `pacman -Syu`。更新时要注意是否有重要新闻。`sysup` 命令会在更新前自动创建 `quicksave-sysup` 快照，如果更新后出现问题可以从任意快照启动项进入系统运行 `quickload` 命令回档。

### 2. 系统清理

`clean` 命令可以清理软件包缓存、回收站、截图、录屏、超数量上限的快照、btrfs 备份子卷等内容。`clean all` 命令可以更进一步，清理所有软件包缓存和所有快照。

home 目录下 `.cache` 内的文件也都是可以安全删除的缓存，不过一股脑删除可能会少用户登录什么的，可以使用 `gdu` 寻找大文件删除。

### 3. 快速存档

活用 btrfs 快照存档。我的 `quicksave` 命令可以快速创建描述为 quicksave 的快照，做不了解的事情记得先快速存档。我设置了合理的快照数量限制，不用担心快照占用磁盘空间，放心存。
