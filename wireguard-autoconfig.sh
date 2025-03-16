#!/bin/bash
echo 'Starting server configuration...'

while [[ $EUID != 0 ]];do
	echo "This script must be run as root."
	exit 1
done

hasWG=$(which wg-quick)
while [[ $hasWG == '' ]];do
    echo 'WireGuard not installed, attempting to install...'
    apt-get install -y wireguard
    break;
done

# Check for systemd-resolved
if ! systemctl is-active --quiet systemd-resolved; then
    echo "systemd-resolved not running, starting it..."
    systemctl start systemd-resolved
    systemctl enable systemd-resolved
fi

hasQR=$(which qrencode)
while [[ $hasQR == '' ]];do
    echo 'qrencode not installed, attempting to install...'
    apt-get install -y qrencode
    break;
done

hasConf=$(ls /etc/wireguard)
while [[ $(echo $hasConf | grep 'wg0.conf') == 'wg0.conf' ]];do
    echo 'wg0.conf already exists, exiting.'
    exit 0
    break;
done

cat << EOF >> /etc/sysctl.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

cd /etc/wireguard

echo 'Generating keypair...'
umask 077
wg genkey | tee privatekey | wg pubkey > publickey
cat << EOF > wg0.conf
[Interface]
PrivateKey = REF_SERVER_KEY
Address = REF_SERVER_ADDRESS
ListenPort = REF_SERVER_PORT
PostUp = iptables -t nat -I POSTROUTING -o enp0s6 -j MASQUERADE # https://docs.vultr.com/how-to-install-wireguard-vpn-on-ubuntu-24-04
PostDown = iptables -t nat -D POSTROUTING -o enp0s6 -j MASQUERADE
EOF
mkdir settings
echo "2" > settings/peer.next
echo 'Please enter the desired server settings below.'
read -p "External WireGuard Port(e.g 51820):" server_port
echo $server_port > settings/port
read -p "Internal Server IPv4 Address(e.g 172.16.16.1):" ipv4_server_addr
ipv4_server_addr="$ipv4_server_addr/24"
echo $ipv4_server_addr > settings/ipv4
sed -i 's;1/24;;g' settings/ipv4

echo 'Determining IPv6 address from date and machine ID...'
ipv6_server_addr="fd$(printf $(date +%s%N)$(cat /var/lib/dbus/machine-id) | sha1sum | tr -d ' -' | cut -c 31-)"
ipv6_server_addr="$(echo $ipv6_server_addr | sed -r 's/.{4}/&:/g')"
echo $ipv6_server_addr > settings/ipv6
ipv6_server_addr="$ipv6_server_addr:1/64"

echo 'Setting Configuration...'
sed -i "s;REF_SERVER_KEY;$(cat privatekey);g" wg0.conf
sed -i "s;REF_SERVER_ADDRESS;$ipv4_server_addr, $ipv6_server_addr;g" wg0.conf
sed -i "s;REF_SERVER_PORT;$server_port;g" wg0.conf
systemctl enable wg-quick@wg0.service

echo 'Done! Run ./add-peer.sh in /etc/wireguard/ to add the first peer and start the server.'
read -p 'A reboot is needed at this point. Reboot now?(y/n)' reboot_now

while [[ $reboot_now == 'y' || $reboot_now == 'Y' || $reboot_now == 'yes' || $reboot_now == 'Yes' ]];do
    reboot
    exit 0
done