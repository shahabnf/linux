apt update
apt upgrade -y
echo "********************"
apt list --upgradable
echo "********************"
apt list --upgradable | cut -d ' ' -f 1 > upgradable.txt
sed -i '1d' upgradable.txt
xargs -a upgradable.txt apt install
rm upgradable.txt
apt autoremove
