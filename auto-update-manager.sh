#!/bin/bash

# =========================
# Auto Update Manager (Production)
# Cross-platform: Debian/Ubuntu + RHEL/CentOS/Alma/Rocky
# =========================

BACKUP_DIR="./backup"
OS_TYPE=""
PKG_MANAGER=""

# =========================
# OS DETECTION
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
    local FILE="$1"
    mkdir -p "$BACKUP_DIR"
    TS=$(date +"%Y%m%d-%H%M%S")

    if [ -f "$FILE" ]; then
        cp "$FILE" "$BACKUP_DIR/$(basename "$FILE")-$TS.bak"
        echo "✔ Backup completed: $BACKUP_DIR/$(basename "$FILE")-$TS.bak"
    fi
}

# =========================
# INSTALL PACKAGES
# =========================
install_updates_pkg() {
    detect_os
    echo "Detected OS: $OS_TYPE"

    if [ "$OS_TYPE" == "debian" ]; then
        apt update && apt install -y unattended-upgrades
    elif [ "$OS_TYPE" == "rhel" ]; then
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
    echo "1) Default (./backup)"
    echo "2) /backup"
    echo "3) /root/backup"
    echo "4) Custom path"

    read -p "Choose: " opt

    case $opt in
        1) BACKUP_DIR="./backup" ;;
        2) BACKUP_DIR="/backup" ;;
        3) BACKUP_DIR="/root/backup" ;;
        4) read -p "Enter custom path: " BACKUP_DIR ;;
        *) BACKUP_DIR="./backup" ;;
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

    echo "Configuring SECURITY-only automatic updates..."

    # -------------------------
    # DEBIAN
    # -------------------------
    if [ "$OS_TYPE" == "debian" ]; then
        FILE="/etc/apt/apt.conf.d/50unattended-upgrades"
        backup_file "$FILE"

        echo "✔ Ensuring security-only updates configuration"

        sed -i 's|// "${distro_id}:${distro_codename}-security";|"${distro_id}:${distro_codename}-security";|' "$FILE"

        # ensure updates are NOT enabled
        sed -i 's|// "${distro_id}:${distro_codename}-updates";||' "$FILE"

        echo "Default schedule: 06:00 AM"

        read -p "Enter update time (HH:MM 24h or 'default'): " TIME

        if [ "$TIME" != "default" ]; then
            mkdir -p /etc/systemd/system/apt-daily-upgrade.timer.d/

            cat > /etc/systemd/system/apt-daily-upgrade.timer.d/override.conf <<EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* $TIME
RandomizedDelaySec=0
Persistent=true
EOF

            systemctl daemon-reload
            systemctl enable --now apt-daily-upgrade.timer

            echo "✔ Update schedule set to $TIME"
        else
            systemctl enable --now apt-daily-upgrade.timer
            echo "✔ Using default schedule (06:00 AM)"
        fi

        backup_file "$FILE"
    fi

    # -------------------------
    # RHEL
    # -------------------------
    if [ "$OS_TYPE" == "rhel" ]; then
        FILE="/etc/dnf/automatic.conf"
        backup_file "$FILE"

        sed -i 's/^upgrade_type.*/upgrade_type = security/' "$FILE"

        echo "Default schedule: 06:00 AM"
        read -p "Enter update time (HH:MM 24h or 'default'): " TIME

        if [ "$TIME" != "default" ]; then
            mkdir -p /etc/systemd/system/dnf-automatic.timer.d/

            cat > /etc/systemd/system/dnf-automatic.timer.d/override.conf <<EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* $TIME
RandomizedDelaySec=0
Persistent=true
EOF

            systemctl daemon-reload
            systemctl enable --now dnf-automatic.timer

            echo "✔ Update schedule set to $TIME"
        else
            systemctl enable --now dnf-automatic.timer
            echo "✔ Using default schedule (06:00 AM)"
        fi

        backup_file "$FILE"
    fi

    # =========================
    # AUTO REBOOT CONFIG
    # =========================
    read -p "Enable automatic reboot after updates? (yes/no/never): " REBOOT

    if [ "$OS_TYPE" == "debian" ]; then
        FILE="/etc/apt/apt.conf.d/50unattended-upgrades"
        backup_file "$FILE"

        if [[ "$REBOOT" == "yes" ]]; then
            sed -i 's|Unattended-Upgrade::Automatic-Reboot ".*";|Unattended-Upgrade::Automatic-Reboot "true";|' "$FILE"
            echo "✔ Auto reboot ENABLED"
        else
            sed -i 's|Unattended-Upgrade::Automatic-Reboot ".*";|Unattended-Upgrade::Automatic-Reboot "false";|' "$FILE"
            echo "✔ Auto reboot DISABLED"
        fi
    fi

    if [ "$OS_TYPE" == "rhel" ]; then
        FILE="/etc/dnf/automatic.conf"
        backup_file "$FILE"

        if [[ "$REBOOT" == "yes" ]]; then
            grep -q "^reboot" "$FILE" && \
                sed -i 's/^reboot.*/reboot = when-needed/' "$FILE" || \
                echo "reboot = when-needed" >> "$FILE"
        else
            grep -q "^reboot" "$FILE" && \
                sed -i 's/^reboot.*/reboot = never/' "$FILE" || \
                echo "reboot = never" >> "$FILE"
        fi

        echo "✔ Reboot setting applied"
    fi

    echo "✔ Configuration completed successfully"
}

# =========================
# TOGGLE UPDATES
# =========================
toggle_updates() {
    detect_os

    echo "1) Disable Updates"
    echo "2) Enable Updates"
    read -p "Choose: " c

    if [ "$OS_TYPE" == "debian" ]; then
        FILE="/etc/apt/apt.conf.d/20auto-upgrades"
        backup_file "$FILE"

        if [ "$c" == "1" ]; then
            sed -i 's/APT::Periodic::Update-Package-Lists "1"/APT::Periodic::Update-Package-Lists "0"/' "$FILE"
            sed -i 's/APT::Periodic::Unattended-Upgrade "1"/APT::Periodic::Unattended-Upgrade "0"/' "$FILE"
            echo "✔ Disabled"
        else
            sed -i 's/APT::Periodic::Update-Package-Lists "0"/APT::Periodic::Update-Package-Lists "1"/' "$FILE"
            sed -i 's/APT::Periodic::Unattended-Upgrade "0"/APT::Periodic::Unattended-Upgrade "1"/' "$FILE"
            echo "✔ Enabled"
        fi
    else
        if [ "$c" == "1" ]; then
            systemctl disable --now dnf-automatic.timer
            echo "✔ Disabled"
        else
            systemctl enable --now dnf-automatic.timer
            echo "✔ Enabled"
        fi
    fi
}

# =========================
# CUSTOM REBOOT SERVICE
# =========================
create_reboot_service() {
    detect_os

    echo "Creating scheduled reboot (only if required)."

    read -p "Enter day (Mon-Sun): " DAY
    read -p "Enter time (HH:MM 24h): " TIME

    DAY=$(echo "$DAY" | awk '{print substr(toupper($1),1,1) tolower(substr($1,2))}')

    systemctl disable --now weekly-reboot.timer 2>/dev/null

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

    cat > /etc/systemd/system/weekly-reboot.service <<EOF
[Unit]
Description=Conditional Reboot Service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/reboot-if-required.sh
EOF

    cat > /etc/systemd/system/weekly-reboot.timer <<EOF
[Unit]
Description=Weekly Conditional Reboot Timer

[Timer]
OnCalendar=$DAY *-*-* $TIME:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now weekly-reboot.timer

    echo "✔ Reboot scheduled: $DAY at $TIME"
}

# =========================
# SERVICE STATUS
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
# HEALTH SUMMARY
# =========================
health_summary() {
    detect_os

    echo "===== System Health Summary ====="

    if [ "$OS_TYPE" == "debian" ]; then
        UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "Listing" | wc -l)
        SEC=$(apt list --upgradable 2>/dev/null | grep "security" | wc -l)
    else
        UPDATES=$(dnf check-update 2>/dev/null | grep -E '^[a-zA-Z0-9]' | wc -l)
        SEC=$(dnf updateinfo list security 2>/dev/null | grep -v "Last " | wc -l)
    fi

    REBOOT="NO"
    [ -f /var/run/reboot-required ] && REBOOT="YES"

    echo "Pending updates: $UPDATES"
    echo "Security updates: $SEC"
    echo "Reboot required: $REBOOT"
}

# =========================
# MAIN MENU
# =========================
while true; do
    echo ""
    echo "===== Auto Update Manager ====="
    echo "0) Detect OS Type"
    echo "1) Install Update Package"
    echo "2) Set Backup Location"
    echo "3) Configure Automatic Updates"
    echo "4) Enable/Disable Updates"
    echo "5) Create Reboot Schedule"
    echo "6) View Logs"
    echo "7) Service Status"
    echo "8) Restart Services"
    echo "9) System Health Summary"
    echo "10) Exit"
    echo "================================"

    read -p "Choose: " opt

    case $opt in
        0) detect_os; echo "$OS_TYPE - $(uname -r)" ;;
        1) install_updates_pkg ;;
        2) set_backup_location ;;
        3) configure_updates ;;
        4) toggle_updates ;;
        5) create_reboot_service ;;
        6) view_logs ;;
        7) check_services ;;
        8) restart_services ;;
        9) health_summary ;;
        10) exit ;;
        *) echo "Invalid option" ;;
    esac
done