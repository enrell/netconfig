#!/usr/bin/env bash

################################################################################
#                    IPTables DNAT - Configuração Exata                       #
#                                                                              #
# Configuração EXATA que funciona:                                            #
# - PC recebe IP 10.42.0.41 na interface LAN                                  #
# - Todo tráfego da WLAN é redirecionado para 10.42.0.41                      #
# - Sem restrições de porta ou protocolo                                      #
#                                                                              #
# USO:                                                                         #
#   sudo ./iptables-dnat-working.sh enp1s0 wlan0                              #
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
echo "  IPTables DNAT - Working Config"
echo "========================================="
echo ""
echo "WLAN: $WLAN_IF ($WLAN_IP)"
echo "LAN:  $ETH_IF (10.42.0.1)"
echo "PC:   10.42.0.41 (service IP)"
echo ""

# 1. Add the service IP on enp1s0
echo "1. Configurando IP 10.42.0.1 em $ETH_IF..."
ip addr flush dev "$ETH_IF" 2>/dev/null || true
ip addr add 10.42.0.1/24 dev "$ETH_IF"
ip link set "$ETH_IF" up

# 2. Enable IPv4 forwarding
echo "2. Habilitando IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null

# 3. iptables: unrestricted DNAT + routing
echo "3. Configurando iptables..."

# Flush old rules
iptables -F
iptables -t nat -F
iptables -t mangle -F

# Fully permissive base policy
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT

# (Optional but typical)
# Allow 10.42.0.0/24 to reach the internet via wlan0 using NAT
iptables -t nat -A POSTROUTING -s 10.42.0.0/24 -o "$WLAN_IF" -j MASQUERADE

# 🔥 Unrestricted DNAT:
# Any packet that comes IN via wlan0 (any port, any protocol)
# will be sent to 10.42.0.41
iptables -t nat -A PREROUTING -i "$WLAN_IF" -j DNAT --to-destination 10.42.0.41

# Allow forwarding between wlan0 and enp1s0 for that traffic
iptables -A FORWARD -i "$WLAN_IF" -o "$ETH_IF" -d 10.42.0.41 -j ACCEPT
iptables -A FORWARD -i "$ETH_IF" -o "$WLAN_IF" -s 10.42.0.41 -j ACCEPT

echo ""
echo "✓ Configurado!"
echo ""
echo "════════════════════════════════════════"
echo "  COMO FUNCIONA"
echo "════════════════════════════════════════"
echo ""
echo "Dispositivos na WLAN (192.168.0.x):"
echo "  • Acessam: $WLAN_IP:QUALQUER_PORTA"
echo "  • DNAT redireciona para: 10.42.0.41"
echo "  • Seus serviços devem ouvir em 10.42.0.41"
echo ""
echo "PRÓXIMO PASSO NO PC:"
echo "  ip addr add 10.42.0.41/24 dev <interface_do_pc>"
echo "  ip link set <interface_do_pc> up"
echo ""
echo "TESTAR:"
echo "  Do celular: http://$WLAN_IP:8096"
echo "  → Redireciona para 10.42.0.41:8096"
echo ""
echo "Verificar regras:"
echo "  iptables -t nat -L -v -n"
echo "  iptables -L -v -n"
echo ""
echo "════════════════════════════════════════"
