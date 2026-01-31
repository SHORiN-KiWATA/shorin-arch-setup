
## 使用方法

1. 安装一个archlinux系统

2. 登录之后从tty运行以下命令
    

    - 短链接（原版）

        ```
        bash <(curl -L is.gd/shorinsetup)
        ```
        
    - 手动克隆

        ```
        # 1. 安装 git
        sudo pacman -Syu git

        # 2. 克隆仓库
        git clone https://github.com/ignent/shorin-arch-setup.git

        # 3. 进入目录并运行
        cd shorin-arch-setup
        sudo bash install.sh
        ```
        一条命令版

        ```
        sudo pacman -Syu git && git clone https://github.com/ignent/shorin-arch-setup.git && cd shorin-arch-setup && sudo bash install.sh
        ```

## 更新计划

- 增加quickshell可选

    - dms post config

