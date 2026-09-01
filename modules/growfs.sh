#!/usr/bin/env bash
# modules/growfs.sh — 首启自动扩容根分区 + 根文件系统(需求 8)
# 两段机制,各自独立、均幂等:
#  1) 分区:systemd-repart 读 /etc/repart.d/*.conf,Type=root 是本架构 DPS 根分区
#     (按架构自动解析:x86-64↔4F68…、ARM-64↔B921…,lib/disk.sh 分区 GUID 同口径)
#     的别名,与 p3 分区类型 GUID 匹配,首启扩分区
#     (已扩满则日志 "No changes")。Type 只能用 DPS 名称——写成 linux-root 会被拒
#     ("Failed to parse partition type",qemu 实测)。
#  2) 文件系统:fstab 根行补 x-systemd.growfs → 首启 fstab-generator 生成
#     /run/systemd/generator/-.mount.wants/systemd-growfs-root.service 接线
#     + local-fs.target.d/ 排序 drop-in(2026-08-17 hx370 真机实测);
#     该单元 After=systemd-repart.service,先扩分区再在线扩 fs。
# 教训(2026-08-17 hx370 真机,fs 卡在镜像大小 94.7G/分区已 930G):
#  - genfstab 不记录 x-* 挂载选项:内核丢弃 x-*(util-linux 只写 utab),
#    genfstab 只读 /proc/self/mountinfo——挂载时带 x-systemd.growfs 无效,
#    必须装完后直接改 fstab(lib/disk.sh 旧注释/旧挂载选项是错的,已删)
#  - genfstab 用空格对齐列宽,字段带尾部空格($2 是 "/          " 不是 "/"),
#    匹配必须 trim
#  - repart 没有 GrowFileSystem 这个配置 key(261 的 man 与 binary 均无,静默忽略),
#    旧配置该行是无效字段,已删
# 无需装额外包:systemd-repart.service 与 systemd-growfs-root.service 均由
# systemd 包自带(静态单元,前者 sysinit.target.wants 拉起,后者靠 fstab 选项接线)。

mod_install() {
    log "写入 systemd-repart 扩容配置"
    chroot_write_file /etc/repart.d/50-root.conf <<'EOF'
[Partition]
Type=root
EOF

    log "fstab 根行补 x-systemd.growfs(genfstab 不记录 x-* 挂载选项)"
    awk 'BEGIN{FS=OFS="\t"}
        function trim(s){gsub(/ +$/,"",s); return s}
        trim($2)=="/" && trim($3)=="btrfs" && $4 !~ /x-systemd\.growfs/ \
            {$4=$4 ",x-systemd.growfs"}
        {print}' "${MNT_DIR}/etc/fstab" >"${MNT_DIR}/etc/fstab.growfs-new"
    # 行数不减 + 确实写入选项,防 awk 转义/匹配错误产出坏 fstab
    # (2026-08-17 远程修机器时 awk 引号转义错误曾产出空文件,踩过)
    (( $(wc -l <"${MNT_DIR}/etc/fstab.growfs-new") >= $(wc -l <"${MNT_DIR}/etc/fstab") )) \
        || die "fstab 补丁行数异常,中止(原 fstab 未动)"
    grep -q x-systemd.growfs "${MNT_DIR}/etc/fstab.growfs-new" \
        || die "fstab 补丁未匹配到根 btrfs 行,中止(原 fstab 未动)"
    mv "${MNT_DIR}/etc/fstab.growfs-new" "${MNT_DIR}/etc/fstab"
}
