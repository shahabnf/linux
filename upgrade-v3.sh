#!/bin/bash

# Detect package manager
if command -v apt > /dev/null; then
    PKG_MANAGER="apt"
elif command -v yum > /dev/null; then
    PKG_MANAGER="yum"
elif command -v dnf >/dev/null; then
    PKG_MANAGER="dnf"
else
    echo "Unsupported package manager. Exiting."
    exit 1
fi

# Update and upgrade system based on the package manager
sudo $PKG_MANAGER update -y

if [ "$PKG_MANAGER" = "apt" ]; then
    sudo $PKG_MANAGER upgrade -y
    echo "********************"
    sudo $PKG_MANAGER list --upgradable
    echo "********************"
    sudo $PKG_MANAGER list --upgradable | cut -d ' ' -f 1 > upgradable.txt
    sed -i '1d' upgradable.txt
    xargs -a upgradable.txt $PKG_MANAGER install -y
    rm upgradable.txt
fi

# Clean up - Remove unused packages
$PKG_MANAGER autoremove -y

# Get the system's IP address
IP_ADDRESS=$(hostname -I | awk '{print $1}')
echo ""
echo "🌐 hostname IP address is $IP_ADDRESS"