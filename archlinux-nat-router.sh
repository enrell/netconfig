#!/usr/bin/env bash

################################################################################
#                    Arch Linux NAT Router (LiveUSB)                           #
#                                                                              #
# Setup rápido para transformar notebook em roteador NAT                      #
# Otimizado para LiveUSB - sem persistência de config                         #
#                                                                              #
# PRÉ-REQUISITOS:                                                              #
#   • Arch Linux em LiveUSB/LiveCD                                            #
#   • Wi-Fi conectada                                                         #
#   • 2 interfaces de rede (Ethernet + Wi-Fi)                                 #
#                                                                              #
# USO:                                                                         #
#   sudo ./archlinux-nat-router.sh                 # Auto-detect               #
#   sudo ./archlinux-nat-router.sh enp3s0 wlp4s0   # Especificar interfaces   #
#                                                                              #
################################################################################

set -euo pipefail

# Trap para capturar erros
trap 'echo -e "\n${RED}[ERRO]${NC} Falha na linha $LINENO. Comando: $BASH_COMMAND"; exit 1' ERR

# Interfaces (auto-detect se vazio)
ETH_IF="${1:-}"
WLAN_IF="${2:-}"

# Rede LAN
LAN_GATEWAY="10.42.0.1"
LAN_NETMASK="24"
DHCP_START="10.42.0.10"
DHCP_END="10.42.0.100"

# ============================================================================
# CORES PARA OUTPUT
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "\n${PURPLE}» $1${NC}\n"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Execute como root"
        exit 1
    fi
    log_info "Verificação de root OK"
}

# ============================================================================
# DETECÇÃO DE INTERFACES
# ============================================================================

detect_eth_interface() {
    log_info "Procurando interface Ethernet..."
    local iface
    for iface in $(ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' ' | grep -v 'lo'); do
        if ! iw dev "$iface" info &>/dev/null; then
            echo "$iface"
            return 0
        fi
    done
    return 1
}

detect_wlan_interface() {
    log_info "Procurando interface Wi-Fi..."
    if command -v iw &>/dev/null; then
        local wlan=$(iw dev 2>/dev/null | grep "Interface" | awk '{print $2}' | head -n1)
        if [[ -n "$wlan" ]]; then
            echo "$wlan"
            return 0
        fi
    fi
    return 1
}

# ============================================================================
# VALIDAÇÃO DE INTERFACES
# ============================================================================

validate_interfaces() {
    log_step "Validando Interfaces"

    if [[ -z "$ETH_IF" ]]; then
        ETH_IF=$(detect_eth_interface) || ETH_IF=""
    fi
    
    if [[ -z "$WLAN_IF" ]]; then
        WLAN_IF=$(detect_wlan_interface) || WLAN_IF=""
    fi

    if [[ -z "$ETH_IF" ]] || [[ -z "$WLAN_IF" ]]; then
        log_error "Não foi possível detectar interfaces"
        log_info "Uso: $0 [eth_interface] [wlan_interface]"
        echo ""
        echo "Interfaces disponíveis:"
        ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' '
        exit 1
    fi

    if ! ip link show "$ETH_IF" &>/dev/null; then
        log_error "Interface $ETH_IF não existe"
        exit 1
    fi
    
    if ! ip link show "$WLAN_IF" &>/dev/null; then
        log_error "Interface $WLAN_IF não existe"
        exit 1
    fi

    log_success "Interfaces validadas: $ETH_IF (LAN) + $WLAN_IF (WAN)"
}

# ============================================================================
# INSTALAÇÃO DE DEPENDÊNCIAS
# ============================================================================

install_dependencies() {
    log_step "Instalando Dependências"

    local packages=("iproute2" "nftables" "dnsmasq")
    
    for pkg in "${packages[@]}"; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            log_info "Instalando $pkg..."
            if ! pacman -S --needed --noconfirm "$pkg" 2>&1; then
                log_error "Erro ao instalar $pkg"
                exit 1
            fi
        else
            log_info "$pkg já instalado"
        fi
    done

    log_success "Dependências OK"
}

# ============================================================================
# CONFIGURAÇÃO DE INTERFACE ETHERNET
# ============================================================================

configure_eth_interface() {
    log_step "Configurando Ethernet ($ETH_IF)"

    ip link set "$ETH_IF" up
    ip addr flush dev "$ETH_IF" 2>/dev/null || true
    ip addr add "$LAN_GATEWAY/$LAN_NETMASK" dev "$ETH_IF"

    sleep 1
    ip addr show "$ETH_IF" | grep -q "inet $LAN_GATEWAY" && log_success "Ethernet: $LAN_GATEWAY/$LAN_NETMASK" || {
        log_error "Falha ao configurar $ETH_IF"
        exit 1
    }
}

# ============================================================================
# HABILITAR IP FORWARDING
# ============================================================================

enable_ip_forwarding() {
    log_step "Habilitando IP Forwarding"

    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null
    sysctl -w net.ipv4.conf.default.rp_filter=0 > /dev/null

    log_success "IP Forwarding ativo"
}

# ============================================================================
# CONFIGURAÇÃO DO FIREWALL (nftables)
# ============================================================================

setup_nftables() {
    log_step "Configurando Firewall (nftables)"

    log_info "Limpando regras anteriores..."
    nft flush ruleset 2>/dev/null || true

    log_info "Criando tabela nat_router..."
    nft add table inet nat_router || { log_error "Falha ao criar tabela"; exit 1; }
    
    log_info "Criando chains..."
    nft add chain inet nat_router input { type filter hook input priority 0\; policy accept\; } || { log_error "Falha na chain input"; exit 1; }
    nft add chain inet nat_router forward { type filter hook forward priority 0\; policy accept\; } || { log_error "Falha na chain forward"; exit 1; }
    nft add chain inet nat_router postrouting { type nat hook postrouting priority 100\; policy accept\; } || { log_error "Falha na chain postrouting"; exit 1; }
    
    log_info "Adicionando regra de masquerade..."
    nft add rule inet nat_router postrouting oifname "$WLAN_IF" masquerade || { log_error "Falha no masquerade"; exit 1; }

    log_success "nftables: Masquerade em $WLAN_IF"
}

# ============================================================================
# CONFIGURAÇÃO DO DNSMASQ
# ============================================================================

setup_dnsmasq() {
    log_step "Configurando DHCP/DNS (dnsmasq)"

    log_info "Criando arquivo de configuração..."
    cat > /etc/dnsmasq.conf <<EOF
interface=$ETH_IF
except-interface=lo
dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,12h
dhcp-option=option:router,$LAN_GATEWAY
server=8.8.8.8
server=8.8.4.4
dhcp-option=option:dns-server,8.8.8.8,8.8.4.4
listen-address=127.0.0.1,$LAN_GATEWAY
bind-interfaces
cache-size=1000
EOF

    log_info "Reiniciando dnsmasq..."
    if systemctl restart dnsmasq 2>&1; then
        log_success "dnsmasq: Pool $DHCP_START-$DHCP_END"
    else
        log_error "Falha ao iniciar dnsmasq"
        systemctl status dnsmasq --no-pager || true
        exit 1
    fi
}

# ============================================================================
# CONFIGURAÇÃO AUTOBOOT COM SYSTEMD
# ============================================================================

setup_systemd_autoboot() {
    log_step "Configurando Autoboot (systemd service)"

    # Criar serviço nat-router
    cat > /etc/systemd/system/nat-router.service <<'EOF'
[Unit]
Description=NAT Router Service for Arch Linux
After=network-online.target nftables.service dnsmasq.service
Wants=network-online.target
Before=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c '\
    echo "Starting NAT Router..."; \
    ip link set ETH_IF up 2>/dev/null || true; \
    ip addr add LAN_GATEWAY/LAN_NETMASK dev ETH_IF 2>/dev/null || true; \
    sysctl -w net.ipv4.ip_forward=1 > /dev/null; \
    nft -f /etc/nftables.conf; \
    systemctl restart dnsmasq; \
    echo "NAT Router started"'

ExecStop=/usr/bin/bash -c '\
    echo "Stopping NAT Router..."; \
    systemctl stop dnsmasq; \
    ip addr del LAN_GATEWAY/LAN_NETMASK dev ETH_IF 2>/dev/null || true; \
    nft flush ruleset; \
    echo "NAT Router stopped"'

Restart=no

[Install]
WantedBy=multi-user.target
EOF

    # Substituir placeholders
    sed -i "s/ETH_IF/$ETH_IF/g" /etc/systemd/system/nat-router.service
    sed -i "s|LAN_GATEWAY|$LAN_GATEWAY|g" /etc/systemd/system/nat-router.service
    sed -i "s/LAN_NETMASK/$LAN_NETMASK/g" /etc/systemd/system/nat-router.service

    # Recarregar systemd
    systemctl daemon-reload

    # Habilitar no boot
    systemctl enable nat-router.service

    log_success "Serviço nat-router criado e habilitado"
    log_info "  • Inicia automaticamente no boot"
    log_info "  • Comando: sudo systemctl status nat-router"
}

# ============================================================================
# VALIDAÇÃO E RESUMO
# ============================================================================

validate_setup() {
    log_step "Status Final"

    echo "✓ Ethernet ($ETH_IF): $(ip -4 addr show "$ETH_IF" | grep -oE 'inet [^ ]*' | awk '{print $2}')"
    echo "✓ IP Forwarding: $(cat /proc/sys/net/ipv4/ip_forward)"
    echo "✓ Firewall: $(nft list ruleset 2>/dev/null | head -1 || echo 'OK')"
    echo "✓ DHCP: $(systemctl is-active dnsmasq)"
    echo ""
    echo "Conecte o PC via Ethernet e configure:"
    echo "  • Linux: sudo dhclient eth0"
    echo "  • Windows: DHCP (automático)"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo "========================================="
    echo "  Arch Linux NAT Router (LiveUSB)"
    echo "========================================="
    echo ""
    
    log_info "Iniciando setup..."
    
    check_root
    validate_interfaces
    install_dependencies
    configure_eth_interface
    enable_ip_forwarding
    setup_nftables
    setup_dnsmasq
    validate_setup
    
    echo ""
    log_success "Setup concluído com sucesso!"
}

main "$@"
