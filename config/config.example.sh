#!/usr/bin/env bash
# config/config.example.sh — 个人配置模板
# 用法:cp config/config.example.sh config/config.sh 然后按需修改
# 约定:模块只读 MY_* 变量;变量为空则对应功能跳过。

# ---- 必填 ----
MY_USERNAME=""                    # 登录用户名(必填)

# ---- 基础 ----
MY_HOSTNAME=""                    # 空则用默认 archlinux
MY_TIMEZONE="Asia/Shanghai"
MY_SSH_PORT=""                    # 空则 22
# ssh 公钥(必填,至少一个;密码登录已禁用,没有公钥装完无法登录)
MY_SSH_PUBKEYS=(
    # "ssh-ed25519 AAAA... you@host"
)

# ---- secrets 处理(镜像默认 copy,物理盘默认 firstboot)----
# copy      = 安装时从宿主机 rsync ~/.ssh ~/.gnupg(仅限镜像/本机物理盘)
# firstboot = 首启通过 systemd 一次性 unit + 已有备份恢复
# keyfile   = 用户提供 git-crypt 对称密钥文件,dotfiles 用 https clone + git-crypt unlock
# none      = 不处理
MY_SECRETS_MODE=""                # 空则用上述默认
MY_BACKUP_TARGET=""               # 例 rsync://192.168.1.1/backup/hostname,backup/firstboot 用
MY_GITCRYPT_KEY_FILE=""           # keyfile 模式:git-crypt 对称密钥路径
MY_DOTFILES_REPO=""               # 例 git@github.com:You/dotfiles.git 或 https://github.com/You/dotfiles

# ---- 桌面 ----
MY_GREETER_AUTOLOGIN=0            # 1=autologin(仅家中台式机;笔记本必须 0)
MY_GPU_MODULES=""                 # 例 "gpu-amd" 或 "gpu-nvidia gpu-intel",自动加入 extra-modules
MY_GPGPU=""                       # GPGPU 计算栈:amd|nvidia|intel,需配合 --extra-modules gpgpu;
                                  # 空=不装。amd=ROCm(OpenCL+HIP),nvidia=OpenCL+CUDA toolkit,
                                  # intel=NEO OpenCL/Level Zero。均含 ocl-icd+clinfo+opencl-headers

# ---- 可选个性化 ----
MY_NTP_SERVERS=""                 # 额外 NTP 服务器(空格分隔)
MY_EXTRA_PACKAGES=""              # 追加包(不分模块的零散包,谨慎使用)
MY_SWAP_SIZE="4G"                 # mem-zswap 后备 btrfs swapfile 大小;"0"=改用 zram(不建 swapfile)
MY_KERNEL_PARAMS=""               # 追加内核参数,写到 boot entry options 行尾(空格分隔)。
                                  # 例:AMD iGPU 跑 LLM 扩 GTT(勿用已废弃的 amdgpu.gttsize):
                                  # "ttm.pages_limit=14680064 ttm.page_pool_size=14680064"(=56G,页数=GB×262144)

# ---- CachyOS(仅 --distro cachyos)----
MY_CACHYOS_MIRRORLIST=""          # 自有 cachyos mirrorlist 文件路径;空则装官方 cachyos-(v3/v4-)mirrorlist 包
MY_CACHYOS_CDN=""                 # keyring/mirrorlist 包的 CDN 基址;空则 cdn77。中国大陆可用
                                  # https://mirrors.ustc.edu.cn/cachyos/repo/x86_64/cachyos
