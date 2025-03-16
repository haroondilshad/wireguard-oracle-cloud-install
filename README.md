# WireGuard for Oracle Cloud

Wireguard VPN Setup for Oracle Cloud Instances  
Oracle Cloud instances need some additional configuration to get WireGuard up and running as expected. Here is how we do that:

> **Special Thanks**: This project was originally created by [@ugurrdemirel](https://github.com/ugurrdemirel). We've made some modifications to support Ubuntu 24.04 and add split tunneling capabilities.

## Ubuntu 24.04 Changes
This fork includes several important changes to support Ubuntu 24.04:
1. Replaced `resolvconf` with `systemd-resolved` for DNS management
2. Simplified NAT routing by using direct iptables commands in PostUp/PostDown:
   ```
   PostUp = iptables -t nat -I POSTROUTING -o enp0s6 -j MASQUERADE
   PostDown = iptables -t nat -D POSTROUTING -o enp0s6 -j MASQUERADE
   ```
   This replaces the previous script-based approach that used helper scripts.

## Please Note: 
- The wireguard kernel mod ships with the latest Ubuntu image on Oracle Cloud.
- The image used for testing is Ubuntu 24.04 and Ubuntu 22.04 Minimal aarch64
- All scripts must be run as root.

## Installation
Install dependencies:
```bash
sudo apt-get update && sudo apt-get install -y wireguard qrencode git
```

Continue as root:
```bash
sudo su
```
Download and install our scripts:
```bash
cd /etc/wireguard
git clone https://github.com/haroondilshad/wireguard-oracle-cloud-install.git
mv wireguard-oracle-cloud-install/* ./
rm -rf wireguard-oracle-cloud-install
```

Generate the config(follow the prompts, this will not start the server):
```bash
./wireguard-autoconfig.sh
```

A reboot is needed at this point. Answer 'y' to the reboot prompt to reboot.

Once you've reconnected to the instance, add a peer and start the server:
```bash
sudo su
cd /etc/wireguard
./add-peer.sh
```

When adding a peer, you'll be prompted to choose between two tunneling modes:
1. Full Tunnel: All traffic from the client will be routed through the VPN
2. Split Tunnel: Only traffic destined for the internal VPN network will be routed through the VPN, while other traffic goes through the client's regular internet connection

You can use the qr code that is output to the terminal or copy the configuration from `/etc/wireguard/peerX`('X' being the peer number). The `add-peer.sh` script will automatically restart the server to apply changes. To add another peer, simply run the script again. Peer configs can found in folders inside `/etc/wireguard/` starting with folder name `peer2`(the peer number corresponds with the peer's IP address).

That's it, you can now connect to the vpn using the auto generated configs :)


## Oracle Cloud IP Policy 

The setup can fail to connect due to Oracle IP Policy set by Oracle Cloud Free Tier. Reddit user [DecisionBright](https://www.reddit.com/user/DecisionBright/) came up with a solution.

0 - disable your firewall temporarily (important during taking these steps):

```bash
sudo ufw disable
```

1 - Go to /etc/iptables/rules.v4

```bash
sudo nano /etc/iptables/rules.v4
```

2 - replace the contents of this file with the following:

```bash
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0] 
:OUTPUT ACCEPT [0:0] 
COMMIT
```

3 - Save the file (CTRL+X > y > Enter) and reboot:

```bash
sudo reboot
```
