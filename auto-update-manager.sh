#!/bin/bash

# =========================
# Auto Update Manager Script
# =========================

BACKUP_DIR="./backup_$(date +%F_%H-%M-%S)"
mkdir -p "$BACKUP_DIR"

CONFIG_FILE_DEB="/etc/apt/apt.conf.d/50unattended-upgrades"
AUTO_FILE_DEB="/etc/apt/apt.conf.d/20auto-upgrades"
DNF_CONF="/etc/dnf/automatic.conf"

OS_TYPE=""

# -------------------------
# Detect OS
# -------------------------
detect_os() {
    if [ -f /etc/debian_version ]; then
        OS_TYPE="debian"
    elif [ -f /etc/redhat-release ]; then
        OS_TYPE="rhel"
    else
        echo "Unsupported OS"
        exit 1
    fi
    echo "Detected OS: $OS_TYPE"
}

# -------------------------
# Backup function
# -------------------------
backup_file() {
    FILE=$1
    if [ -f "$FILE" ]; then
        cp "$FILE" "$BACKUP_DIR/"
    fi
}

# -------------------------
# Install packages
# -------------------------
install_updates() {
    detect_os

    if [ "$OS_TYPE" = "debian" ]; then
        apt update
        apt install -y unattended-upgrades
        dpkg-reconfigure unattended-upgrades
    elif [ "$OS_TYPE" = "rhel" ]; then
        dnf install -y dnf-automatic
        systemctl enable --now dnf-automatic.timer
    fi
}

# -------------------------
# Configure auto updates
# -------------------------
configure_updates() {
    detect_os

    read -p "Enable automatic reboot? (yes/no): " REBOOT

    if [ "$OS_TYPE" = "debian" ]; then
        backup_file "$CONFIG_FILE_DEB"

        sed -i 's#Unattended-Upgrade::Automatic-Reboot .*#Unattended-Upgrade::Automatic-Reboot "false";#' "$CONFIG_FILE_DEB"

        if [ "$REBOOT" = "yes" ]; then
            read -p "Enter reboot time (HH:MM 24h): " TIME

            sed -i "s#Unattended-Upgrade::Automatic-Reboot.*#Unattended-Upgrade::Automatic-Reboot \"true\";#" "$CONFIG_FILE_DEB"

            grep -q Automatic-Reboot-Time "$CONFIG_FILE_DEB" || \
            echo "Unattended-Upgrade::Automatic-Reboot-Time \"$TIME\";" >> "$CONFIG_FILE_DEB"
        fi

        echo 'APT::Periodic::Unattended-Upgrade "1";' > "$AUTO_FILE_DEB"
        echo 'APT::Periodic::Update-Package-Lists "1";' >> "$AUTO_FILE_DEB"

    elif [ "$OS_TYPE" = "rhel" ]; then
        backup_file "$DNF_CONF"

        sed -i 's/apply_updates = no/apply_updates = yes/' "$DNF_CONF"
    fi
}

# -------------------------
# Set systemd timer override
# -------------------------
set_schedule() {
    read -p "Enter update time (HH:MM 24h): " TIME

    systemctl edit apt-daily-upgrade.timer <<EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* $TIME
RandomizedDelaySec=0
EOF

    systemctl daemon-reexec
    systemctl restart apt-daily-upgrade.timer

    echo "Update schedule set to $TIME"
}

# -------------------------
# Create weekly reboot
# -------------------------
create_weekly_reboot() {
    read -p "Enter day (e.g., Sat): " DAY
    read -p "Enter time (HH:MM 24h): " TIME

    cat <<EOF > /etc/systemd/system/weekly-reboot.service
[Unit]
Description=Weekly Reboot if Required

[Service]
Type=oneshot
ExecStart=/bin/bash -c '[ -f /var/run/reboot-required ] && /sbin/reboot'
EOF

    cat <<EOF > /etc/systemd/system/weekly-reboot.timer
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

    echo "Weekly reboot scheduled on $DAY at $TIME"
}

# -------------------------
# Disable auto updates
# -------------------------
disable_updates() {
    detect_os

    if [ "$OS_TYPE" = "debian" ]; then
        backup_file "$AUTO_FILE_DEB"
        echo 'APT::Periodic::Unattended-Upgrade "0";' > "$AUTO_FILE_DEB"
    elif [ "$OS_TYPE" = "rhel" ]; then
        systemctl disable --now dnf-automatic.timer
    fi

    read -p "Create custom reboot schedule? (yes/no): " CHOICE
    if [ "$CHOICE" = "yes" ]; then
        create_weekly_reboot
    fi
}

# -------------------------
# View logs
# -------------------------
view_logs() {
    detect_os

    if [ "$OS_TYPE" = "debian" ]; then
        tail -n 30 /var/log/unattended-upgrades/unattended-upgrades.log
    elif [ "$OS_TYPE" = "rhel" ]; then
        journalctl -u dnf-automatic --no-pager | tail -n 30
    fi
}

# -------------------------
# Menu
# -------------------------
while true; do
    echo ""
    echo "===== Auto Update Manager ====="
    echo "1) Install Auto Update Package"
    echo "2) Configure Auto Updates"
    echo "3) Set Update Schedule"
    echo "4) Disable Auto Updates + Optional Reboot Timer"
    echo "5) View Logs"
    echo "6) Exit"
    echo "================================"

    read -p "Choose an option: " OPTION

    case $OPTION in
        1) install_updates ;;
        2) configure_updates ;;
        3) set_schedule ;;
        4) disable_updates ;;
        5) view_logs ;;
        6) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
done