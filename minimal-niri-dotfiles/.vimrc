"显示行号
set number
"显示相对行号
set relativenumber
"高亮当前行
set cursorline
"语法高亮
syntax on 

" 开启自动缩进，新的一行会自动与上一行对齐
set autoindent
" 在输入搜索词时，实时高亮显示匹配项（增量搜索）
set incsearch

" 高亮显示所有搜索结果
set hlsearch

" 搜索时忽略大小写
set ignorecase

" 如果搜索词中包含了大写字母，则自动切换为大小写敏感搜索
set smartcase
" 开启持久化撤销（undo），即使关闭再打开文件，也能撤销之前的更改
set undofile

" undo目录
silent !mkdir -p ~/.cache/vim/undo
set undodir=~/.cache/vim/undo

" === 将 y (yank 复制) 映射到系统剪贴板 (+ 寄存器) ===
nnoremap y "+y
vnoremap y "+y
nnoremap Y "+Y

" === 将 x (剪切单个字符/选中块) 映射到系统剪贴板 ===
nnoremap x "+x
vnoremap x "+x

" === 可选：如果你希望 p (paste 粘贴) 默认从系统剪贴板粘贴 ===
" 因为你把 y 和 x 放到了系统剪贴板，你通常也会希望 p 直接粘贴系统剪贴板的内容
nnoremap p "+p
vnoremap p "+p
nnoremap P "+P
vnoremap P "+P

" 接管鼠标事件
set mouse=a

" === fcitx5 状态切换与恢复 ===
let g:fcitx_state = 1
autocmd InsertLeave * let g:fcitx_state = system("fcitx5-remote")[0] | call job_start("fcitx5-remote -c")
autocmd InsertEnter * if g:fcitx_state == '2' | call job_start("fcitx5-remote -o") | endif
autocmd VimEnter * call job_start("fcitx5-remote -c")
