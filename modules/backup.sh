#!/usr/bin/env bash
# modules/backup.sh — rsync 备份脚本 + systemd timer
# 读取变量:MY_BACKUP_TARGET(如 rsync://<nas>/backup/machines;空则整个模块跳过)
# enable 服务:backup.timer

mod_install() {
    if [[ -z ${MY_BACKUP_TARGET:-} ]]; then
        info "MY_BACKUP_TARGET 未设置,跳过 backup 模块"
        return 0
    fi
    pacman_install rsync
    chroot_write_file /opt/backup.sh <<EOF
#!/bin/bash
set -euo pipefail
rsync -av --delete /mnt/system/ArchLinux/ --exclude /boot --exclude /efi ${MY_BACKUP_TARGET}/"\$(hostname)"
rsync -av --delete /efi/ ${MY_BACKUP_TARGET}/"\$(hostname)"/efi
rsync -av --delete /boot/ ${MY_BACKUP_TARGET}/"\$(hostname)"/boot
sync
echo 3 >/proc/sys/vm/drop_caches
EOF
    chmod 755 "${MNT_DIR}/opt/backup.sh"
    chroot_write_file /etc/systemd/system/backup.service <<'EOF'
[Unit]
Description=daily backup
After=network.target

[Service]
User=root
Group=root
Type=oneshot
KillMode=process
ExecStart=/opt/backup.sh
Restart=on-failure
RestartSec=3
EOF
    chroot_write_file /etc/systemd/system/backup.timer <<'EOF'
[Unit]
Description=daily backup
ConditionVirtualization=!container

[Timer]
OnCalendar=Mon..Fri 08:00:00
AccuracySec=5h
RandomizedDelaySec=43200
Persistent=true

[Install]
WantedBy=timers.target
EOF
    chroot_enable backup.timer
}
