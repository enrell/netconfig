#!/usr/bin/env bash

################################################################################
#                    IPTables Bridge - Redirecionamento Total                 #
#                                                                              #
# Redireciona TODO o tráfego do notebook para o PC na LAN                     #
# 4 comandos simples - sem firula                                             #
#                                                                              #
# USO:                                                                         #
#   sudo ./iptables-bridge.sh enp1s0 wlp4s0                                   #
#                                                                              #
################################################################################

set -euo pipefail

ETH_IF="${1:-}"
WLAN_IF="${2:-}"

if [[ $EUID -ne 0 ]]; then
    echo "Execute como root"
    exit 1
fi

if [[ -z "$ETH_IF" ]] || [[ -z "$WLAN_IF" ]]; then
    echo "Uso: $0 <eth_interface> <wlan_interface>"
    echo ""
    echo "Interfaces disponíveis:"
    ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' '
    exit 1
fi

WLAN_IP=$(ip -4 addr show "$WLAN_IF" | grep -oP 'inet \K[0-9.]+' | head -1)

if [[ -z "$WLAN_IP" ]]; then
    echo "Interface Wi-Fi '$WLAN_IF' não tem IP"
    exit 1
fi

echo "========================================="
echo "  IPTables Bridge - Total Redirect"
echo "========================================="
echo ""
echo "Configurando redirecionamento total:"
echo "  $WLAN_IP (notebook) → 10.42.0.0/24 (LAN)"
echo ""

# 1. IP Forwarding - TOTAL
echo "1. Habilitando IP Forwarding..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
sysctl -w net.ipv4.conf.all.rp_filter=0 > /dev/null

# 2. DNAT - Redireciona TODO tráfego para a subnet LAN
echo "2. Configurando DNAT (redirect)..."
iptables -t nat -A PREROUTING -d "$WLAN_IP" -j DNAT --to-destination 10.42.0.0/24

# 3. FORWARD - Aceita tudo
echo "3. Liberando FORWARD..."
iptables -A FORWARD -j ACCEPT

# 4. MASQUERADE - Reescreve origem para respostas funcionarem
echo "4. Configurando MASQUERADE..."
iptables -t nat -A POSTROUTING -o "$WLAN_IF" -j MASQUERADE
iptables -t nat -A POSTROUTING -o "$ETH_IF" -j MASQUERADE

echo ""
echo "✓ Configurado!"
echo ""
echo "ACESSO:"
echo "  Do celular: http://$WLAN_IP:8096"
echo "  Redireciona: PC na LAN (10.42.0.x)"
echo ""
echo "Verificar regras:"
echo "  iptables -t nat -L -v -n"
echo "  iptables -L -v -n"
echo ""
echo "Limpar regras:"
echo "  iptables -F"
echo "  iptables -t nat -F"
echo "========================================="
