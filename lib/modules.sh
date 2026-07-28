#!/usr/bin/env bash
# lib/modules.sh — 模块元数据读取、依赖闭包、conflicts 校验、拓扑排序、执行
# 全局输出:RESOLVED_MODULES(排好序的模块名数组)

MODULES_DIR=${MODULES_DIR:-$SCRIPT_DIR/modules}
PROFILES_DIR=${PROFILES_DIR:-$SCRIPT_DIR/profiles}

# 子 shell 读取模块元数据,输出 "requires|conflicts|before"(空格分隔,空字段留空)
mod_read_meta() {
    local name=$1
    local file=$MODULES_DIR/$name.sh
    [[ -f $file ]] || die "模块不存在: $name($file)"
    (
        # shellcheck disable=SC1090
        source "$file"
        local r="" c="" b=""
        declare -F mod_requires >/dev/null && r=$(mod_requires)
        declare -F mod_conflicts >/dev/null && c=$(mod_conflicts)
        declare -F mod_before >/dev/null && b=$(mod_before)
        printf '%s|%s|%s' "$r" "$c" "$b"
    )
}

_meta_field() { # meta field_index(1|2|3)
    cut -d'|' -f"$2" <<<"$1"
}

# 排序权重:核心模块固定靠前,desktop-* 固定靠后,其余按声明顺序
_mod_rank() {
    local name=$1 i
    local fixed=(base pacman growfs ssh audio fonts ime)
    for i in "${!fixed[@]}"; do
        [[ $name == "${fixed[$i]}" ]] && {
            echo "$i"
            return
        }
    done
    [[ $name == desktop-* ]] && {
        echo 1000
        return
    }
    echo 100
}

resolve_modules() {
    local profile=${1:-${PROFILE:-}}
    local profile_conf=$PROFILES_DIR/$profile.conf
    [[ -f $profile_conf ]] || die "profile 不存在: $profile($profile_conf)"
    # shellcheck disable=SC1090
    MODULES=()
    source "$profile_conf"

    # desktop 占位符 → desktop-$DESKTOP
    local i
    for i in "${!MODULES[@]}"; do
        [[ ${MODULES[$i]} == desktop ]] && MODULES[$i]=desktop-$DESKTOP
    done

    # MY_GPU_MODULES 自动并入 extra;EXTRA/SKIP 为逗号分隔字符串,先归一化为数组
    local extra=() skip_arr=()
    read -ra extra <<<"$(csv_to_list "${EXTRA_MODULES:-}")"
    [[ -n ${MY_GPU_MODULES:-} ]] && read -ra _gpu <<<"$MY_GPU_MODULES" && extra+=("${_gpu[@]}")
    read -ra skip_arr <<<"$(csv_to_list "${SKIP_MODULES:-}")"

    # 最终集合 = profile + extra - skip(保持声明顺序去重)
    local -A want=() skip=()
    local m
    for m in ${skip_arr[@]+"${skip_arr[@]}"}; do skip[$m]=1; done
    local candidates=()
    for m in "${MODULES[@]}" "${extra[@]}"; do
        [[ -n ${skip[$m]:-} || -n ${want[$m]:-} ]] && continue
        want[$m]=1
        candidates+=("$m")
    done

    # requires 闭包(可能引入新模块,循环直到收敛)
    local -A meta=()
    local changed=1
    while ((changed)); do
        changed=0
        for m in "${candidates[@]}"; do
            [[ -z ${meta[$m]:-} ]] && meta[$m]=$(mod_read_meta "$m")
            local req
            for req in $(_meta_field "${meta[$m]}" 1); do
                if [[ -z ${want[$req]:-} ]]; then
                    want[$req]=1
                    candidates+=("$req")
                    changed=1
                fi
            done
        done
    done
    # 补读后加模块的元数据
    for m in "${candidates[@]}"; do
        [[ -z ${meta[$m]:-} ]] && meta[$m]=$(mod_read_meta "$m")
    done

    # conflicts 校验
    for m in "${candidates[@]}"; do
        local c
        for c in $(_meta_field "${meta[$m]}" 2); do
            [[ -n ${want[$c]:-} ]] && die "模块冲突: $m 与 $c 不能同时安装"
        done
    done

    # 拓扑排序:约束 = requires(依赖在前) + mod_before(声明者在前)
    RESOLVED_MODULES=()
    local -A seen=()
    local remaining=("${candidates[@]}")
    while ((${#remaining[@]})); do
        local picked="" best_rank=99999
        for m in "${remaining[@]}"; do
            # 有未完成的依赖则阻塞
            local blocked=0 dep other
            for dep in $(_meta_field "${meta[$m]}" 1); do
                [[ -n ${want[$dep]:-} && -z ${seen[$dep]:-} ]] && {
                    blocked=1
                    break
                }
            done
            ((blocked)) && continue
            # 有未完成的模块声明 before 本模块则阻塞
            for other in "${remaining[@]}"; do
                [[ $other == "$m" ]] && continue
                local b
                for b in $(_meta_field "${meta[$other]}" 3); do
                    [[ $b == "$m" ]] && {
                        blocked=1
                        break
                    }
                done
                ((blocked)) && break
            done
            ((blocked)) && continue
            local rank
            rank=$(_mod_rank "$m")
            if ((rank < best_rank)); then
                best_rank=$rank
                picked=$m
            fi
        done
        [[ -z $picked ]] && die "模块依赖存在循环: ${remaining[*]}"
        RESOLVED_MODULES+=("$picked")
        seen[$picked]=1
        local next=()
        for m in "${remaining[@]}"; do [[ $m != "$picked" ]] && next+=("$m"); done
        remaining=("${next[@]}")
    done
}

mod_exec() {
    local name=$1
    local file=$MODULES_DIR/$name.sh
    log "==> 模块: $name"
    # shellcheck disable=SC1090
    source "$file"
    declare -F mod_install >/dev/null || die "$name 缺少 mod_install()"
    mod_install
    unset -f mod_install mod_requires mod_conflicts mod_before 2>/dev/null || true
}
