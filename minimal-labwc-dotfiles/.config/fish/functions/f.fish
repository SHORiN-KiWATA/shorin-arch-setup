function f
    # ==============================================================================
    # 脚本功能说明
    # 1. 结合 Fastfetch，在终端启动时展示随机二次元图片。
    # 2. 具备静默后台异步下载机制，库存不足时自动补货，绝不阻塞前台终端的启动。
    # 3. 具备智能缓存管理机制，自动控制待展示区与已使用区的图片数量上限。
    # 4. 具备极致的网络环境容错处理，无网或弱网时自动降级，避免死等。
    # 5. 具备自动清理 Fastfetch 内部生成的图片转换缓存功能，防止磁盘空间无感膨胀。
    # ==============================================================================

    # ================= 配置区域 =================
    
    # 开关：阅后即焚模式，针对 Fastfetch 内部缓存
    # true  = 运行后强力清空 ~/.cache/fastfetch/images/，防止转码缓存膨胀
    # false = 保留缓存
    set -l CLEAN_CACHE_MODE true
    
    # 每次补货下载多少张
    set -l DOWNLOAD_BATCH_SIZE 10
    # 最大库存上限，即待展示区
    set -l MAX_CACHE_LIMIT 100
    # 库存少于多少张时开始补货
    set -l MIN_TRIGGER_LIMIT 60
    
    # used 目录最大存放数量
    # 超过此数量将按照时间顺序删除最旧的文件
    set -l MAX_USED_LIMIT 50
    
    # ===========================================

    # --- 0. 语言与提示语配置 ---
    
    set -l IS_ZH true
    if not string match -q -r "^zh" "$LANG"
        set IS_ZH false
    end

    set -l MSG_WAIT "库存不够啦！正在去搬运新的图片，请稍等哦..."
    set -l MSG_NET_ERR "网络好像不太通畅，无法下载新图片 QAQ"
    set -l MSG_FAIL "图片获取失败了，这次只能先显示默认的 Logo 啦 QAQ"

    if test "$IS_ZH" = false
        set MSG_WAIT "Out of stock! Fetching new images, please wait..."
        set MSG_NET_ERR "Network seems unstable, cannot download new images QAQ"
        set MSG_FAIL "Failed to get image, falling back to default Logo QAQ"
    end
    
    # --- 1. 参数解析与模式设置 ---
    
    set -l ARGS_FOR_FASTFETCH
    for arg in $argv
        # 拦截帮助指令
        if test "$arg" = "-h"; or test "$arg" = "--help"
            if test "$IS_ZH" = true
                echo "========================================================"
                echo "    f - 随机二次元美少女生成器暨 Fastfetch 终端看板娘"
                echo "========================================================"
                echo ""
                echo "用法模式："
                echo "  f       : 标准模式。随机生成一张美少女图片同时显示系统信息。"
                echo "  fwatch  : 持续运行模式。适合挂在副屏当作动态看板娘。"
                echo ""
                echo "进阶技巧："
                echo "  你可以直接在命令后追加原生 fastfetch 的参数。"
                echo "  例如 f --logo-width 40 可以单独控制本次生成的图片宽度。"
                echo "========================================================"
            else
                echo "========================================================"
                echo "    f - Random Anime Girl Generator and Fastfetch Mascot"
                echo "========================================================"
                echo ""
                echo "Usage Modes:"
                echo "  f       : Standard mode. Spawns a random safe for work anime girl for your terminal."
                echo "  fwatch  : Continuous mode. Use with the watch command, perfect for a secondary monitor mascot."
                echo ""
                echo "Advanced Tips:"
                echo "  You can append native fastfetch arguments directly after the command."
                echo "  For example, f --logo-width 40 will control the width of the generated image."
                echo "========================================================"
            end
            return 0
        else
            set -a ARGS_FOR_FASTFETCH $arg
        end
    end
    
    # --- 2. 目录配置 ---
    
    # 根据模式区分缓存目录和锁文件
    set -l CACHE_DIR "$HOME/.cache/fastfetch_waifu"
    set -l LOCK_FILE "/tmp/fastfetch_waifu.lock"
    
    # 定义已使用目录
    set -l USED_DIR "$CACHE_DIR/used"
    
    mkdir -p "$CACHE_DIR"
    mkdir -p "$USED_DIR"
    
    # --- 3. 核心函数 ---

    # 抛弃脆弱的 1.1.1.1，使用苹果的全球探针节点，并使用 -I 极限提速
    function check_network
        curl -sI --connect-timeout 2 "http://captive.apple.com/hotspot-detect.html" >/dev/null 2>&1
        return $status
    end
    
    function get_random_url
        set -l TIMEOUT --connect-timeout 5 --max-time 15
        set -l RAND (math (random) % 3 + 1)
        
        # === SFW 正常 API ===
        switch $RAND
            case 1
                curl -s $TIMEOUT "https://api.waifu.im/images?IncludedTags=waifu&IsNsfw=false" | jq -r '.images[0].url'
            case 2
                curl -s $TIMEOUT "https://nekos.best/api/v2/waifu" | jq -r '.results[0].url'
            case 3
                curl -s $TIMEOUT "https://api.waifu.pics/sfw/waifu" | jq -r '.url'
        end
    end
    
    function download_one_image -V CACHE_DIR
        set -l URL (get_random_url)
        if string match -qr "^http" -- "$URL"
            # 使用带时间戳的随机文件名
            set -l FILENAME "waifu_"(date +%s%N)"_"(random)".jpg"
            set -l TARGET_PATH "$CACHE_DIR/$FILENAME"
            
            curl -s -L --connect-timeout 5 --max-time 15 -o "$TARGET_PATH" "$URL"
            
            # 简单校验
            if test -s "$TARGET_PATH"
                if command -v file >/dev/null 2>&1
                    if not file --mime-type "$TARGET_PATH" | grep -q "image/"
                        rm -f "$TARGET_PATH"
                    end
                end
            else
                rm -f "$TARGET_PATH"
            end
        end
    end
    
    function background_job -V CACHE_DIR -V LOCK_FILE -V MIN_TRIGGER_LIMIT -V DOWNLOAD_BATCH_SIZE -V MAX_CACHE_LIMIT
        # 导出函数定义以便在 fish -c 中使用
        set -l get_random_url_def (functions get_random_url | string collect)
        set -l download_one_image_def (functions download_one_image | string collect)
        set -l check_network_def (functions check_network | string collect)
        
        fish -c "
            # 忽略终端关闭带来的 SIGHUP 信号
            trap '' HUP

            # 重新定义需要的函数
            $get_random_url_def
            $download_one_image_def
            $check_network_def
            
            # 使用 flock 防止并发
            flock -n 200 || exit 1

            # 网络检查，没网就悄悄退出，不占后台资源
            if not check_network
                exit 0
            end
            
            # 导入变量
            set CACHE_DIR '$CACHE_DIR'
            
            # 1. 补货检查
            set CURRENT_COUNT (find \$CACHE_DIR -maxdepth 1 -name '*.jpg' 2>/dev/null | wc -l)
            
            if test \$CURRENT_COUNT -lt $MIN_TRIGGER_LIMIT
                for i in (seq 1 $DOWNLOAD_BATCH_SIZE)
                    download_one_image
                    sleep 0.5
                end
            end
            
            # 2. 清理过多库存
            set FINAL_COUNT (find \$CACHE_DIR -maxdepth 1 -name '*.jpg' 2>/dev/null | wc -l)
            if test \$FINAL_COUNT -gt $MAX_CACHE_LIMIT
                set DELETE_START_LINE (math $MAX_CACHE_LIMIT + 1)
                ls -tp \$CACHE_DIR/*.jpg 2>/dev/null | tail -n +\$DELETE_START_LINE | xargs -I {} rm -- '{}'
            end
        " 200>"$LOCK_FILE" &
        
        # 将刚才丢入后台的 fish 子进程剥离终端控制
        disown
    end
    
    # --- 4. 主程序逻辑 ---
    
    set -l FILES $CACHE_DIR/*.jpg
    set -l NUM_FILES (count $FILES)
    
    # fish 若无匹配文件，$FILES 可能为空或保留模式字符串，需额外判断
    if test "$NUM_FILES" -eq 1; and not test -f "$FILES[1]"
        set NUM_FILES 0
        set FILES
    end
    
    set -l SELECTED_IMG ""
    
    if test "$NUM_FILES" -gt 0
        # 有库存，随机选一张
        set -l RAND_INDEX (math (random) % $NUM_FILES + 1)
        set SELECTED_IMG "$FILES[$RAND_INDEX]"
        
        # 后台补货
        background_job >/dev/null 2>&1
    else
        # 没库存，输出多语言提示语并增加网络连通性容错
        echo "$MSG_WAIT"
        
        if check_network
            download_one_image
        else
            echo "$MSG_NET_ERR"
        end
        
        set FILES $CACHE_DIR/*.jpg
        if test -f "$FILES[1]"
            set SELECTED_IMG "$FILES[1]"
            background_job >/dev/null 2>&1
        end
    end
    
    # 运行 Fastfetch
    if test -n "$SELECTED_IMG"; and test -f "$SELECTED_IMG"
        # 显示图片
        fastfetch --logo "$SELECTED_IMG" --logo-preserve-aspect-ratio true $ARGS_FOR_FASTFETCH
        
        # === 逻辑: 移动到 used 目录 ===
        mv "$SELECTED_IMG" "$USED_DIR/"
        
        # === 逻辑: 检查 used 目录并清理旧图 ===
        set -l used_files $USED_DIR/*.jpg
        set -l used_count (count $used_files)
        
        # 再次确认 count
        if test "$used_count" -gt 0; and not test -f "$used_files[1]"
             set used_count 0
        end

        if test "$used_count" -gt "$MAX_USED_LIMIT"
            # 计算需要跳过的行数
            set -l skip_lines (math "$MAX_USED_LIMIT" + 1)
            
            # 列出所有文件按时间倒序，取尾部，删除
            set -l files_to_delete (ls -tp "$USED_DIR"/*.jpg 2>/dev/null | tail -n +$skip_lines)
            
            if test -n "$files_to_delete"
                rm -- $files_to_delete
            end
        end

        # 检查是否开启清理 Fastfetch 内部缓存
        if test "$CLEAN_CACHE_MODE" = true
            # 仅删除缩略图缓存，保留原图
            rm -rf "$HOME/.cache/fastfetch/images"
        end
    else
        # 失败提示语
        echo "$MSG_FAIL"
        fastfetch $ARGS_FOR_FASTFETCH
    end
end
