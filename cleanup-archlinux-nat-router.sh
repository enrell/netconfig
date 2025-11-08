#!/usr/bin/env bash

################################################################################
#                    NAT Router Cleanup Script                                 #
#                                                                              #
# Remove TODAS as configurações de rede do NAT Router                         #
# Reseta interfaces, firewall, forwarding - exceto wpa_supplicant             #
#                                                                              #
# USO:                                                                         #
#   sudo ./cleanup-archlinux-nat-router.sh                                    #
#                                                                              #
################################################################################

set -euo pipefail

# ============================================================================
# CORES
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

# ============================================================================
# VERIFICAR ROOT
# ============================================================================

if [[ $EUID -ne 0 ]]; then
    log_error "Execute como root: sudo $0"
    exit 1
fi

# ============================================================================
# PARAR SERVIÇOS
# ============================================================================

stop_services() {
    log_step "Parando Serviços"
    
    if systemctl is-active --quiet nat-router 2>/dev/null; then
        log_info "Parando nat-router.service..."
        systemctl stop nat-router
        log_success "nat-router.service parado"
    else
        log_info "nat-router.service não está ativo"
    fi
    
    if systemctl is-active --quiet dnsmasq 2>/dev/null; then
        log_info "Parando dnsmasq..."
        systemctl stop dnsmasq
        log_success "dnsmasq parado"
    else
        log_info "dnsmasq não está ativo"
    fi
}

# ============================================================================
# DESABILITAR SERVIÇOS NO BOOT
# ============================================================================

disable_services() {
    log_step "Desabilitando Serviços do Boot"
    
    if systemctl is-enabled --quiet nat-router 2>/dev/null; then
        log_info "Desabilitando nat-router.service..."
        systemctl disable nat-router
        log_success "nat-router.service desabilitado"
    else
        log_info "nat-router.service já estava desabilitado"
    fi
    
    if systemctl is-enabled --quiet dnsmasq 2>/dev/null; then
        log_info "Desabilitando dnsmasq..."
        systemctl disable dnsmasq
        log_success "dnsmasq desabilitado"
    else
        log_info "dnsmasq já estava desabilitado"
    fi
}

# ============================================================================
# REMOVER ARQUIVOS DE SERVIÇO
# ============================================================================

remove_service_files() {
    log_step "Removendo Arquivos de Configuração"
    
    if [[ -f /etc/systemd/system/nat-router.service ]]; then
        log_info "Removendo /etc/systemd/system/nat-router.service..."
        rm -f /etc/systemd/system/nat-router.service
        log_success "Arquivo de serviço removido"
    else
        log_info "Arquivo de serviço não encontrado"
    fi
    
    if [[ -f /etc/nftables.conf ]]; then
        log_info "Removendo /etc/nftables.conf..."
        rm -f /etc/nftables.conf
        log_success "Configuração do nftables removida"
    else
        log_info "nftables.conf não encontrado"
    fi
    
    if [[ -f /etc/dnsmasq.conf ]]; then
        log_info "Removendo /etc/dnsmasq.conf..."
        rm -f /etc/dnsmasq.conf
        log_success "Configuração do dnsmasq removida"
    else
        log_info "dnsmasq.conf não encontrado"
    fi
    
    systemctl daemon-reload
    log_success "systemd recarregado"
}

# ============================================================================
# LIMPAR REGRAS DO FIREWALL
# ============================================================================

flush_firewall() {
    log_step "Limpando Firewall (nftables)"
    
    log_info "Removendo todas as regras do nftables..."
    nft flush ruleset 2>/dev/null || true
    log_success "Regras do nftables limpas"
}

# ============================================================================
# DESABILITAR IP FORWARDING
# ============================================================================

disable_ip_forwarding() {
    log_step "Desabilitando IP Forwarding"
    
    sysctl -w net.ipv4.ip_forward=0 > /dev/null
    sysctl -w net.ipv6.conf.all.forwarding=0 > /dev/null
    
    log_success "IP Forwarding desabilitado"
}

# ============================================================================
# LIMPAR CONFIGURAÇÃO DE INTERFACES
# ============================================================================

cleanup_interfaces() {
    log_step "Limpando Configuração de Interfaces"
    
    # Remover todos os IPs da subnet 10.42.0.0/24 de todas as interfaces
    log_info "Procurando IPs 10.42.0.x em interfaces..."
    
    while IFS= read -r line; do
        iface=$(echo "$line" | awk '{print $NF}')
        ip=$(echo "$line" | awk '{print $2}')
        
        log_info "Removendo $ip de $iface..."
        ip addr del "$ip" dev "$iface" 2>/dev/null || true
        log_success "IP removido de $iface"
    done < <(ip -4 addr show | grep "inet 10.42.0" || true)
    
    # Flush de todas as rotas relacionadas à subnet
    log_info "Removendo rotas para 10.42.0.0/24..."
    ip route del 10.42.0.0/24 2>/dev/null || true
    
    log_success "Interfaces resetadas"
}

# ============================================================================
# RESETAR RP FILTER
# ============================================================================

reset_rp_filter() {
    log_step "Resetando Configurações de Kernel"
    
    log_info "Restaurando rp_filter..."
    sysctl -w net.ipv4.conf.default.rp_filter=1 > /dev/null
    sysctl -w net.ipv4.conf.all.rp_filter=1 > /dev/null
    
    log_success "Parâmetros do kernel restaurados"
}

# ============================================================================
# VERIFICAR LIMPEZA
# ============================================================================

verify_cleanup() {
    log_step "Verificando Limpeza"
    
    echo "Status dos serviços:"
    echo "  • nat-router: $(systemctl is-active nat-router 2>/dev/null || echo 'inactive')"
    echo "  • dnsmasq: $(systemctl is-active dnsmasq 2>/dev/null || echo 'inactive')"
    echo ""
    echo "IP Forwarding:"
    echo "  • IPv4: $(cat /proc/sys/net/ipv4/ip_forward)"
    echo "  • IPv6: $(cat /proc/sys/net/ipv6/conf/all/forwarding)"
    echo ""
    echo "RP Filter:"
    echo "  • default: $(cat /proc/sys/net/ipv4/conf/default/rp_filter)"
    echo "  • all: $(cat /proc/sys/net/ipv4/conf/all/rp_filter)"
    echo ""
    echo "Regras nftables:"
    if nft list ruleset 2>/dev/null | grep -q "table"; then
        log_warn "Ainda existem regras no nftables!"
        nft list ruleset
    else
        log_success "Nenhuma regra ativa"
    fi
    echo ""
    echo "Interfaces com IP 10.42.0.x:"
    if ip -4 addr show | grep -q "inet 10.42.0"; then
        log_warn "Ainda existem IPs configurados:"
        ip -4 addr show | grep "inet 10.42.0"
    else
        log_success "Nenhuma interface com IP da LAN"
    fi
    echo ""
    echo "Rotas para 10.42.0.0/24:"
    if ip route show | grep -q "10.42.0.0/24"; then
        log_warn "Ainda existem rotas:"
        ip route show | grep "10.42.0.0/24"
    else
        log_success "Nenhuma rota configurada"
    fi
}

# ============================================================================
# MENU DE CONFIRMAÇÃO
# ============================================================================

confirm_cleanup() {
    echo "========================================="
    echo "  NAT Router Cleanup"
    echo "========================================="
    echo ""
    log_warn "Esta ação irá:"
    echo "  • Parar nat-router e dnsmasq"
    echo "  • Desabilitar serviços no boot"
    echo "  • Remover arquivos de configuração"
    echo "  • Limpar TODAS as regras do firewall"
    echo "  • Desabilitar IP forwarding"
    echo "  • Remover TODOS os IPs 10.42.0.x"
    echo "  • Remover rotas da subnet 10.42.0.0/24"
    echo "  • Resetar parâmetros do kernel (rp_filter)"
    echo ""
    log_info "NÃO será alterado:"
    echo "  • wpa_supplicant (Wi-Fi permanece conectado)"
    echo ""
    read -p "Continuar? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelado pelo usuário"
        exit 0
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    confirm_cleanup
    
    stop_services
    disable_services
    remove_service_files
    flush_firewall
    disable_ip_forwarding
    reset_rp_filter
    cleanup_interfaces
    verify_cleanup
    
    echo ""
    log_success "Sistema de rede completamente resetado!"
    echo ""
    log_info "Estado atual:"
    echo "  • Firewall: limpo (sem regras)"
    echo "  • Forwarding: desabilitado"
    echo "  • Interfaces: sem IPs 10.42.0.x"
    echo "  • Wi-Fi: mantido conectado"
    echo ""
    log_info "Para reativar o NAT Router:"
    echo "  sudo ./archlinux-nat-router.sh <eth_interface> <wlan_interface>"
}

main "$@"
