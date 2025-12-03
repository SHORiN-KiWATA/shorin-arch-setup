
## 使用方法

1. 安装一个archlinux系统

2. 登录之后从tty运行以下命令

    - 全球用户
        
        ```
        # 1. 安装 git
        sudo pacman -Sy git

        # 2. 克隆仓库
        git clone https://github.com/SHORiN-KiWATA/shorin-arch-setup.git

        # 3. 进入目录并运行
        cd shorin-arch-setup
        sudo bash install.sh
        ```
        - 一条命令版

            ```
            sudo pacman -S git && git clone https://github.com/SHORiN-KiWATA/shorin-arch-setup.git && cd shorin-arch-setup && sudo bash install.sh
            ```

    - 可选：使用中国大陆github镜像站

        如果连不上git，可以使用github镜像站，用环境变量激活

        ```
        # 1. 使用镜像站克隆仓库
        sudo pacman -Sy git
        git clone https://gitclone.com/github.com/SHORiN-KiWATA/shorin-arch-setup.git

        # 2. 进入目录
        cd shorin-arch-setup

        # 3. 开启 CN_MIRROR 环境变量运行
        sudo CN_MIRROR=1 bash install.sh
        ```
        - 一条命令版

            ```
            sudo pacman -Sy git && git clone https://gitclone.com/github.com/SHORiN-KiWATA/shorin-arch-setup.git && cd shorin-arch-setup && sudo CN_MIRROR=1 bash install.sh
            ```
