if status is-interactive
    # Commands to run in interactive sessions can go here
end
set fish_greeting ""
fish_add_path ~/.local/bin
starship init fish | source
zoxide init fish --cmd cd | source

function y
	set tmp (mktemp -t "yazi-cwd.XXXXXX")
	yazi $argv --cwd-file="$tmp"
	if read -z cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
		builtin cd -- "$cwd"
	end
	rm -f -- "$tmp"
end

function cat
	command bat --theme="base16" -- $argv
end

function ls
	command eza --icons=auto -- $argv
end

function lt
	command eza --icons=auto --tree -- $argv
end

function la
	command eza -l --icons=auto -- $argv
end
# grub
abbr grub 'LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 sudo grub-mkconfig -o /boot/grub/grub.cfg'
# 小黄鸭补帧 需要steam安装正版小黄鸭
abbr lsfg 'LSFG_PROCESS="miyu"'
# fa运行fastfetch
abbr fa fastfetch
abbr reboot 'systemctl reboot'
function sl 
	command sl | lolcat	
end
function 滚
	sysup 
end
function raw
	command ~/.local/bin/random-anime-wallpaper-noctalia $argv
end

# Added by LM Studio CLI (lms)
set -gx PATH $PATH /home/shorin/.lmstudio/bin
# End of LM Studio CLI section
