#!/bin/bash

# Version 2.0

# =========================
# GLOBAL VARIABLES
# =========================
BACKUP_DIR="./backup"
OS_TYPE=""
PKG_MANAGER=""

# =========================
# DETECT OS
# =========================
detect_os() {
    if [ -f /etc/debian_version ]; then
        OS_TYPE="debian"
        PKG_MANAGER="apt"
    elif [ -f /etc/redhat-release ]; then
        OS_TYPE="rhel"
        PKG_MANAGER="dnf"
    else
        OS_TYPE="unknown"
    fi
}

# =========================
# BACKUP FUNCTION
# =========================
backup_file() {
    FILE=$1
    mkdir -p "$BACKUP_DIR"
    TS=$(date +"%Y%m%d-%H%M%S")

    if [ -f "$FILE" ]; then
        DEST="$BACKUP_DIR/$(basename "$FILE")-$TS.bak"
        cp "$FILE" "$DEST"
        echo "✔ Backup completed: $DEST"
    fi
}

# =========================
# INSTALL PACKAGES
# =========================
install_updates_pkg() {
    detect_os
    echo "Detected OS: $OS_TYPE"

    if [ "$OS_TYPE" == "debian" ]; then
        echo "Installing unattended-upgrades (automatic security updates)..."
        apt update && apt install -y unattended-upgrades

    elif [ "$OS_TYPE" == "rhel" ]; then
        echo "Installing dnf-automatic (automatic updates)..."
        dnf install -y dnf-automatic
        systemctl enable --now dnf-automatic.timer

    else
        echo "Unsupported OS"
    fi
}

# =========================
# SET BACKUP LOCATION
# =========================
set_backup_location() {
    echo "Select backup location:"
    echo "1) Use default (./backup)"
    echo "2) Use /backup"
    echo "3) Use /root/backup"
    echo "4) Enter custom path"

    read -p "Choose an option: " choice

    case $choice in
        1) BACKUP_DIR="./backup" ;;
        2) BACKUP_DIR="/backup" ;;
        3) BACKUP_DIR="/root/backup" ;;
        4)
            read -p "Enter custom backup path: " input
            BACKUP_DIR="$input"
            ;;
        *) echo "Invalid option. Using default."; BACKUP_DIR="./backup" ;;
    esac

    BACKUP_DIR="${BACKUP_DIR%/}"
    mkdir -p "$BACKUP_DIR"

    echo "✔ Backup directory set to $BACKUP_DIR"
}

# =========================
# CONFIGURE UPDATES
# =========================
configure_updates() {
    detect_os

    echo "Configuring automatic SECURITY updates only (no application upgrades)..."

    if [ "$OS_TYPE" == "debian" ]; then
        FILE="/etc/apt/apt.conf.d/50unattended-upgrades"
        backup_file "$FILE"

        sed -i 's|// "\${distro_id}:\${distro_codename}-updates";||' "$FILE"
        echo "✔ Security updates configured (Debian)"

    elif [ "$OS_TYPE" == "rhel" ]; then
        FILE="/etc/dnf/automatic.conf"
        backup_file "$FILE"

        # upgrade_type
        grep -q '^upgrade_type' "$FILE" \
            && sed -i 's/^upgrade_type.*/upgrade_type = security/' "$FILE" \
            || echo "upgrade_type = security" >> "$FILE"

        # apply_updates
        grep -q '^apply_updates' "$FILE" \
            && sed -i 's/^apply_updates.*/apply_updates = yes/' "$FILE" \
            || echo "apply_updates = yes" >> "$FILE"

        # download_updates
        grep -q '^download_updates' "$FILE" \
            && sed -i 's/^download_updates.*/download_updates = yes/' "$FILE" \
            || echo "download_updates = yes" >> "$FILE"

        echo "✔ Security updates (download + apply) configured (RHEL)"
    fi

    echo "Default update time is 06:00 AM"
    read -p "Enter update time (HH:MM 24h) or 'default': " TIME

    if [ "$TIME" != "default" ]; then
        if [ "$OS_TYPE" == "debian" ]; then
            mkdir -p /etc/systemd/system/apt-daily-upgrade.timer.d/

            cat > /etc/systemd/system/apt-daily-upgrade.timer.d/override.conf <<EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* $TIME:00
RandomizedDelaySec=0
Persistent=true
EOF

            systemctl daemon-reload
            systemctl restart apt-daily-upgrade.timer

        elif [ "$OS_TYPE" == "rhel" ]; then
            mkdir -p /etc/systemd/system/dnf-automatic.timer.d/

            cat > /etc/systemd/system/dnf-automatic.timer.d/override.conf <<EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* $TIME:00
RandomizedDelaySec=0
Persistent=true
EOF

            systemctl daemon-reload
            systemctl restart dnf-automatic.timer
        fi

        echo "✔ Update schedule set to $TIME"
    else
        echo "✔ Default schedule retained (06:00 AM)"
    fi

    read -p "Enable automatic reboot after updates? (yes/no): " REBOOT

    if [ "$OS_TYPE" == "debian" ]; then
        FILE="/etc/apt/apt.conf.d/50unattended-upgrades"
        backup_file "$FILE"

        if [[ "$REBOOT" == "yes" ]]; then
            sed -i 's|//Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "true";|' "$FILE"
            echo "✔ Auto reboot ENABLED"
        else
            sed -i 's|Unattended-Upgrade::Automatic-Reboot "true";|Unattended-Upgrade::Automatic-Reboot "false";|' "$FILE"
            echo "✔ Auto reboot DISABLED"
        fi

    elif [ "$OS_TYPE" == "rhel" ]; then
        FILE="/etc/dnf/automatic.conf"
        backup_file "$FILE"

        # reboot setting
        grep -q '^reboot' "$FILE" \
            && sed -i 's/^reboot.*/reboot = '"$([ "$REBOOT" == "yes" ] && echo "when-needed" || echo "never")"'/' "$FILE" \
            || echo "reboot = $([ "$REBOOT" == "yes" ] && echo "when-needed" || echo "never")" >> "$FILE"

        if [[ "$REBOOT" == "yes" ]]; then
            echo "✔ Auto reboot ENABLED"
        else
            echo "✔ Auto reboot DISABLED"
        fi
    fi

    echo "✔ Automatic update configuration completed successfully"
}

# =========================
# ENABLE/DISABLE UPDATES
# =========================
toggle_updates() {
    echo "1) Disable Automatic Updates"
    echo "2) Enable Automatic Updates"
    read -p "Choose: " choice

    detect_os

    if [ "$choice" == "1" ]; then
        if [ "$OS_TYPE" == "debian" ]; then
            sed -i 's/"1"/"0"/g' /etc/apt/apt.conf.d/20auto-upgrades
            systemctl restart apt-daily-upgrade.timer
        else
            systemctl disable --now dnf-automatic.timer
        fi
        echo "✔ Automatic updates DISABLED"

    elif [ "$choice" == "2" ]; then
        if [ "$OS_TYPE" == "debian" ]; then
            sed -i 's/"0"/"1"/g' /etc/apt/apt.conf.d/20auto-upgrades
            systemctl restart apt-daily-upgrade.timer
        else
            systemctl enable --now dnf-automatic.timer
        fi
        echo "✔ Automatic updates ENABLED"
    fi
}

# =========================
# CUSTOM REBOOT SERVICE
# =========================
create_reboot_service() {
    detect_os

    echo "This will create a custom reboot schedule (only if required)."

    read -p "Enter day (Mon-Sun): " DAY
    read -p "Enter time (HH:MM 24h): " TIME

    cat > /usr/local/bin/reboot-if-required.sh <<'EOF'
#!/bin/bash
if [ -f /var/run/reboot-required ]; then
    /sbin/shutdown -r now
elif command -v rpm >/dev/null 2>&1; then
    if [ "$(uname -r)" != "$(rpm -q kernel | tail -1 | sed 's/kernel-//')" ]; then
        /sbin/shutdown -r now
    fi
fi
EOF

    chmod +x /usr/local/bin/reboot-if-required.sh

    systemctl disable --now weekly-reboot.timer 2>/dev/null

    cat > /etc/systemd/system/weekly-reboot.service <<EOF
[Unit]
Description=Weekly Reboot if Required

[Service]
Type=oneshot
ExecStart=/usr/local/bin/reboot-if-required.sh
EOF

    cat > /etc/systemd/system/weekly-reboot.timer <<EOF
[Unit]
Description=Weekly Reboot Timer

[Timer]
OnCalendar=$DAY *-*-* $TIME:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now weekly-reboot.timer

    echo "✔ Custom reboot service created"
}

# =========================
# VIEW LOGS
# =========================
view_logs() {
    detect_os

    if [ "$OS_TYPE" == "debian" ]; then
        tail -30 /var/log/unattended-upgrades/unattended-upgrades.log
    else
        journalctl -u dnf-automatic --no-pager | tail -30
    fi
}

# =========================
# CHECK SERVICES
# =========================
check_services() {
    echo "1) Update service status"
    echo "2) Custom reboot service status"
    read -p "Choose: " c

    detect_os

    if [ "$c" == "1" ]; then
        if [ "$OS_TYPE" == "debian" ]; then
            systemctl status apt-daily-upgrade.timer
        else
            systemctl status dnf-automatic.timer
        fi
    else
        systemctl status weekly-reboot.timer
    fi
}

# =========================
# RESTART SERVICES
# =========================
restart_services() {
    echo "1) Restart update service"
    echo "2) Restart reboot service"
    read -p "Choose: " c

    detect_os

    if [ "$c" == "1" ]; then
        if [ "$OS_TYPE" == "debian" ]; then
            systemctl restart apt-daily-upgrade.timer
        else
            systemctl restart dnf-automatic.timer
        fi
    else
        systemctl restart weekly-reboot.timer
    fi

    echo "✔ Service restarted"
}

# =========================
# SYSTEM HEALTH SUMMARY
# =========================
health_summary() {
    detect_os

    echo "===== System Health Summary ====="

    if [ "$OS_TYPE" == "debian" ]; then
        UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)
        SEC=$(apt list --upgradable 2>/dev/null | grep "security" | wc -l)
    else
        UPDATES=$(dnf check-update 2>/dev/null | grep -E '^[a-zA-Z0-9]' | wc -l)
        SEC=$(dnf -q updateinfo list security --disableplugin=subscription-manager | wc -l)
    fi

    REBOOT="NO"
    if [ -f /var/run/reboot-required ]; then
        REBOOT="YES"
    elif command -v rpm >/dev/null 2>&1; then
        if [ "$(uname -r)" != "$(rpm -q kernel | tail -1 | sed 's/kernel-//')" ]; then
            REBOOT="YES"
        fi
    fi

    echo "Pending updates: $UPDATES"
    echo "Security updates: $SEC"
    echo "Reboot required: $REBOOT"
}

# =========================
# SET TIMEZONE (America/Edmonton)
# =========================
set_timezone_edmonton() {
    echo "This will set the system timezone to America/Edmonton."

    read -p "Proceed? (yes/no): " confirm

    if [[ "$confirm" == "yes" ]]; then
        timedatectl set-timezone America/Edmonton
        echo "✔ Timezone set to America/Edmonton"
        timedatectl
    else
        echo "Operation cancelled."
    fi
}

# =========================
# MAIN MENU
# =========================
while true; do
    echo ""
    echo "===== Auto Update Manager ====="
    echo "0) Detect OS Type"
    echo "1) Install Automatic Update Package"
    echo "2) Set Backup Location"
    echo "3) Configure Automatic Updates"
    echo "4) Disable/Enable Automatic Updates"
    echo "5) Create Custom Reboot Service"
    echo "6) View Logs"
    echo "7) Check Services Status"
    echo "8) Restart Services"
    echo "9) System Health Summary"
    echo "10) Set Timezone to America/Edmonton"
    echo "11) Exit"
    echo "================================"

    read -p "Choose an option: " opt

    case $opt in
        0) detect_os; echo "OS: $OS_TYPE"; echo "Kernel: $(uname -r)" ;;
        1) install_updates_pkg ;;
        2) set_backup_location ;;
        3) configure_updates ;;
        4) toggle_updates ;;
        5) create_reboot_service ;;
        6) view_logs ;;
        7) check_services ;;
        8) restart_services ;;
        9) health_summary ;;
        10) set_timezone_edmonton ;;
        11) exit ;;
        *) echo "Invalid option" ;;
    esac
done