#!/bin/bash
echo 'Starting WireGuard peer configuration...'

while [[ $EUID != 0 ]];do
	echo "This script must be run as root."
	exit 1
done

hasWG=$(which wg-quick)
while [[ $hasWG == '' ]];do
    echo 'WireGuard not installed. Run wireguard-autoconfig.sh first.'
    exit 1
done

if ! systemctl is-active --quiet systemd-resolved; then
    echo "systemd-resolved not running. Starting and enabling the service..."
    systemctl start systemd-resolved
    systemctl enable systemd-resolved
    if ! systemctl is-active --quiet systemd-resolved; then
        echo "Failed to start systemd-resolved. Please check your system configuration."
        exit 1
    fi
fi

hasQR=$(which qrencode)
while [[ $hasQR == '' ]];do
    echo 'qrencode not installed. Run wireguard-autoconfig.sh first.'
    exit 1
done

hasSettings=$(ls /etc/wireguard/settings/peer.next)
while [[ $hasSettings != '/etc/wireguard/settings/peer.next' ]];do
    echo 'Script config not found. Run wireguard-autoconfig.sh first.'
    exit 1
done

cd /etc/wireguard

peerNum=$(cat settings/peer.next)
echo $(($peerNum + 1)) > settings/peer.next

mkdir peer${peerNum}
cd peer${peerNum}

# Ask user for tunnel mode
echo "Please select the tunnel mode:"
echo "1) Full tunnel (route all traffic through VPN)"
echo "2) Split tunnel (only route internal network traffic through VPN)"
read -p "Enter your choice (1 or 2): " tunnel_mode

# Set AllowedIPs based on tunnel mode
if [ "$tunnel_mode" = "1" ]; then
    allowed_ips_conf="0.0.0.0/0, ::/0"
    echo "Configuring full tunnel mode..."
elif [ "$tunnel_mode" = "2" ]; then
    # Get the internal network CIDR from settings
    internal_network_v4="$(cat ../settings/ipv4)0/24"
    # Fix IPv6 address format by removing extra colon
    internal_network_v6="$(cat ../settings/ipv6)/64"
    allowed_ips_conf="$internal_network_v4, $internal_network_v6"
    echo "Configuring split tunnel mode for internal networks: $internal_network_v4, $internal_network_v6"
else
    echo "Invalid choice. Defaulting to full tunnel mode..."
    allowed_ips_conf="0.0.0.0/0, ::/0"
fi

echo 'Generating keypair...'
umask 077
wg genkey | tee privatekey | wg pubkey > publickey
cat << EOF > peer.conf
[Interface]
PrivateKey = REF_PEER_KEY
Address = REF_PEER_ADDRESS
DNS = 1.1.1.2, 1.0.0.2, 2606:4700:4700::1112, 2606:4700:4700::1002

[Peer]
PublicKey = REF_SERVER_PUBLIC_KEY
AllowedIPs = $allowed_ips_conf
Endpoint = REF_SERVER_ENDPOINT
EOF
external_ip=$(curl ipinfo.io/ip)
server_endpoint="$external_ip:$(cat ../settings/port)"
ipv4_peer_addr="$(cat ../settings/ipv4)${peerNum}/24"
ipv6_peer_addr="$(cat ../settings/ipv6)${peerNum}/64"

echo 'Setting peer configuration...'
sed -i "s;REF_PEER_KEY;$(cat privatekey);g" peer.conf
sed -i "s;REF_PEER_ADDRESS;$ipv4_peer_addr, $ipv6_peer_addr;g" peer.conf
sed -i "s;REF_SERVER_PUBLIC_KEY;$(cat ../publickey);g" peer.conf
sed -i "s;REF_SERVER_ENDPOINT;$server_endpoint;g" peer.conf

wg-quick down wg0

echo 'Updating server configuration...'
cat << EOF >> ../wg0.conf

[Peer]
PublicKey = REF_PEER_PUBLIC_KEY
AllowedIPs = REF_PEER_IPS
EOF
allowed_ips="$(cat ../settings/ipv4)${peerNum}/32, $(cat ../settings/ipv6)${peerNum}/128"
sed -i "s;REF_PEER_PUBLIC_KEY;$(cat publickey);g" ../wg0.conf
sed -i "s;REF_PEER_IPS;$allowed_ips;g" ../wg0.conf

wg-quick up wg0

echo "You can connect using the config /etc/wireguard/peer${peerNum}/peer.conf -- or -- the QR code below:"
cat peer.conf | qrencode --type utf8
