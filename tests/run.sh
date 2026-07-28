#!/usr/bin/env bash
# tests/run.sh — 纯 bash 自测(无外部依赖):bash tests/run.sh
set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }
check(){ if eval "$2" &>/dev/null; then ok "$1"; else bad "$1"; fi; }

# ---- 1. 所有 bash 文件语法检查 ----
while IFS= read -r f; do
    check "bash -n $f" "bash -n '$f'"
done < <(find arch-install lib distro modules profiles config tests -type f \( -name '*.sh' -o -name 'arch-install' -o -name '*.conf' \) | sort)

# ---- 2. 模块元数据契约 ----
for m in modules/*.sh; do
    name=$(basename "$m" .sh)
    check "$name 定义 mod_install" "grep -q '^mod_install()' '$m'"
    # requires/conflicts/before 引用的模块必须存在(desktop-kde/niri 等真实模块)
    for fn in mod_requires mod_conflicts mod_before; do
        if grep -q "^$fn()" "$m"; then
            deps=$(bash -c "source '$m'; $fn" 2>/dev/null)
            for d in $deps; do
                check "$name.$fn 引用的 $d 存在" "[[ -f 'modules/$d.sh' ]]"
            done
        fi
    done
done

# ---- 3. profile 引用的模块必须存在(desktop 占位符除外)----
for p in profiles/*.conf; do
    while read -r line; do
        [[ $line =~ ^[a-z-]+$ ]] || continue
        [[ $line == desktop ]] && continue
        check "$p 引用的 $line 存在" "[[ -f 'modules/$line.sh' ]]"
    done < <(grep -v '^\s*#' "$p")
done

# ---- 4. 硬约定:模块内不得硬编码个人信息(检查原脚本里的具体个人值)----
check "无硬编码用户名 steamedfish" "! grep -rn 'steamedfish' modules/ distro/ lib/ arch-install profiles/ | grep -v '^Binary'"
check "无硬编码个人 IP(192.168.1.1/192.168.82.66)" "! grep -rn '192\.168\.1\.1\|192\.168\.82\.66' modules/ distro/ lib/ arch-install profiles/"
check "无硬编码 ssh 端口 32200" "! grep -rn '32200' modules/ distro/ lib/ arch-install profiles/"

# ---- 5. 解析器单测(隔离环境,假模块)----
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/modules" "$TMP/profiles"
cat >"$TMP/modules/a.sh" <<'EOF'
mod_install() { :; }
mod_requires() { echo b; }
EOF
cat >"$TMP/modules/b.sh" <<'EOF'
mod_install() { :; }
EOF
cat >"$TMP/modules/c.sh" <<'EOF'
mod_install() { :; }
mod_before() { echo a; }
mod_conflicts() { echo d; }
EOF
cat >"$TMP/profiles/test.conf" <<'EOF'
MODULES=(a c)
EOF
result=$(
    # shellcheck source=../lib/common.sh
    source lib/common.sh
    SCRIPT_DIR="$TMP"
    DESKTOP=niri EXTRA_MODULES="" SKIP_MODULES="" MY_GPU_MODULES=""
    source lib/modules.sh
    resolve_modules test 2>/dev/null
    echo "${RESOLVED_MODULES[*]}"
)
check "requires 闭包(a→b 自动补全)" "grep -qw b <<<'$result'"
pos_c=$(tr ' ' '\n' <<<"$result" | grep -nx c | cut -d: -f1)
pos_a=$(tr ' ' '\n' <<<"$result" | grep -nx a | cut -d: -f1)
check "mod_before 生效(c 在 a 前)" "[[ -n $pos_c && -n $pos_a && $pos_c -lt $pos_a ]]"

# conflicts 应报错
conflict_err=$(
    source lib/common.sh
    SCRIPT_DIR="$TMP"
    DESKTOP=niri EXTRA_MODULES="d" SKIP_MODULES="" MY_GPU_MODULES=""
    source lib/modules.sh
    mkdir -p "$TMP/modules"; echo 'mod_install() { :; }' >"$TMP/modules/d.sh"
    resolve_modules test 2>&1 >/dev/null || true
)
check "conflicts 检测(c+d 报错)" "grep -q 冲突 <<<'$conflict_err'"

# ---- 6. dry-run(需要临时 config)----
if [[ ! -f config/config.sh ]]; then
    printf 'MY_USERNAME="dryrun-test"\nMY_SSH_PUBKEYS=("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDummyKeyForDryRunOnly dryrun@test")\n' >config/config.sh
    CLEANUP_CONFIG=1
fi
check "dry-run server" "./arch-install --target /tmp/x.img --profile server --dry-run >/dev/null 2>&1"
check "dry-run desktop niri" "./arch-install --target /tmp/x.img --profile desktop --desktop niri --dry-run >/dev/null 2>&1"
check "dry-run cachyos" "./arch-install --target /tmp/x.img --profile server --distro cachyos --cachyos-kernel bore --dry-run >/dev/null 2>&1"
dryrun_out=$(./arch-install --target /tmp/x.img --profile desktop --desktop niri --dry-run 2>/dev/null)
check "dry-run 输出含模块顺序" "grep -q desktop-niri <<<'$dryrun_out'"

# ---- 7. 专项断言 ----
check "debug 模块存在" "[[ -f modules/debug.sh ]]"
check "gaming 含 archlinuxcn 包" "grep -q an-anime-game-launcher-bwrap modules/gaming.sh"
check "cachyos 查询最新版" "grep -q _cachyos_latest_pkg_url distro/cachyos.sh"
check "cachyos 支持自有 mirrorlist" "grep -q MY_CACHYOS_MIRRORLIST distro/cachyos.sh"
check "支持 --cputype" "grep -q -- '--cputype' arch-install"
check "KDE 专属应用在 desktop-kde" "grep -qw dolphin modules/desktop-kde.sh"
if grep -qw 'dolphin\|kate\|tokodon' modules/gui-apps.sh; then
    bad "gui-apps 不应含 KDE 专属应用"
else
    ok "gui-apps 无 KDE 专属应用"
fi
modules_list=$(./arch-install --modules 2>/dev/null)
check "--modules 输出含 desktop-niri" "grep -q desktop-niri <<<'$modules_list'"

# ---- 8. 第二轮需求断言 ----
check "ssh 要求默认公钥" "grep -q MY_SSH_PUBKEYS modules/ssh.sh"
check "ssh 写 authorized_keys" "grep -q authorized_keys modules/ssh.sh"
check "ananicy-cpp 仅 cachyos" "grep -q 'DISTRO == cachyos' modules/gaming.sh"
check "archcn 包接管镜像列表" "grep -q archcn-mirrorlist-git modules/pacman.sh"
check "original 用 pacman-mirrorlist 包" "grep -q 'pacman_install pacman-mirrorlist' modules/pacman.sh"

# ---- 9. 内存选项断言 ----
check "mem-zram 与 mem-zswap 互斥" "grep -q 'echo mem-zswap' modules/mem-zram.sh"
check "mem-zswap 与 mem-zram 互斥" "grep -q 'echo mem-zram' modules/mem-zswap.sh"
check "mem-zram 装 zram-generator" "grep -q 'pacman_install zram-generator' modules/mem-zram.sh"
check "mem-zswap 用 tmpfiles 配置" "grep -q 'tmpfiles.d/zswap.conf' modules/mem-zswap.sh"
check "mem-zswap 启用 zstd" "grep -q 'compressor - - - - zstd' modules/mem-zswap.sh"
check "server profile 默认 mem-zswap" "grep -q mem-zswap profiles/server.conf"
check "desktop profile 默认 mem-zswap" "grep -q mem-zswap profiles/desktop.conf"
[[ ${CLEANUP_CONFIG:-0} == 1 ]] && rm -f config/config.sh

echo
echo "通过 $PASS,失败 $FAIL"
((FAIL == 0))
