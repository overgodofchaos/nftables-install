#!/usr/bin/env bash

# Ensure the script is running in bash
if [[ -z "$BASH_VERSION" ]]; then
    echo "Error: bash required" >&2
    exit 1
fi

set -euo pipefail

# Resolve the script directory path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! [[ -f "$SCRIPT_DIR/install.sh" ]];  then
    echo "Error: The script directory could not be determined correctly."
    exit 1
fi

# Check root
if [[ $EUID -ne 0 ]]; then
  echo "Error: root required" >&2
  exit 1
fi

# Install packages
apt-get update
apt-get install -y jq nftables

# Clean iptables
sudo systemctl disable --now netfilter-persistent.service 2>/dev/null || true
sudo systemctl disable --now iptables.service ip6tables.service 2>/dev/null || true

for cmd in iptables ip6tables iptables-nft ip6tables-nft iptables-legacy ip6tables-legacy; do
  command -v "$cmd" >/dev/null 2>&1 || continue
  for table in filter nat mangle raw security; do
    "$cmd" -t "$table" -F 2>/dev/null || true
    "$cmd" -t "$table" -X 2>/dev/null || true
  done
  "$cmd" -P INPUT ACCEPT 2>/dev/null || true
  "$cmd" -P FORWARD ACCEPT 2>/dev/null || true
  "$cmd" -P OUTPUT ACCEPT 2>/dev/null || true
done

# Docker
[[ ! -f "/etc/docker/daemon.json" ]]; then
    cp "${SCRIPT_DIR}/docker-daemon.json" "/etc/docker/daemon.json"
else
    jq '.firewall-backend = "nftables"' /etc/docker/daemon.json > tmp.json && mv tmp.json /etc/docker.daemon.json
fi

# Install profile
cp "${SCRIPT_DIR}/nftables.conf" "/etc/nftables.conf"
chmod u+x "/etc/nftables.conf"


# Finish
echo "Nftables installed"
echo "Afailable interfaces:"
printf '%s\n' /sys/class/net/* | sed 's|.*/||'
echo "Start:"
echo "nft -f /etc/nftables.conf && systemctl enable --now nftables && systemctl restart docker.service 2>/dev/null || true"
echo "Edit /etc/nftables.com before start"
