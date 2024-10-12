#!/bin/bash

# Detect package manager
if command -v apt > /dev/null; then
    PKG_MANAGER="apt"
elif command -v yum > /dev/null; then
    PKG_MANAGER="yum"
else
    echo "Neither apt nor yum package manager found!"
    exit 1
fi

# Update and upgrade system based on the package manager
if [ "$PKG_MANAGER" = "apt" ]; then
    apt update
    apt upgrade -y
    echo "********************"
    apt list --upgradable
    echo "********************"
    apt list --upgradable | cut -d ' ' -f 1 > upgradable.txt
    sed -i '1d' upgradable.txt
    xargs -a upgradable.txt apt install -y
    rm upgradable.txt
    apt autoremove -y

elif [ "$PKG_MANAGER" = "yum" ]; then
    yum update -y
    echo "********************"
    yum check-update
    echo "********************"
    yum list updates | awk '{print $1}' > upgradable.txt
    sed -i '1d' upgradable.txt
    xargs -a upgradable.txt yum install -y
    rm upgradable.txt
    yum autoremove -y
fi
