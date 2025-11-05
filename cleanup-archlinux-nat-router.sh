#!/usr/bin/env bash

################################################################################
#                  Arch Linux NAT Router Cleanup Script                        #
#                                                                              #
# Remove todas as configurações de NAT Router instaladas pelo script setup    #
#                                                                              #
# USO:                                                                         #
#   sudo ./cleanup-archlinux-nat-router.sh         # Limpeza com confirmação  #
#   sudo ./cleanup-archlinux-nat-router.sh --force # Limpeza sem perguntar    #
#                                                                              #
################################################################################

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Opções
FORCE_CLEANUP="${1:-}"

# ============================================================================
# FUNÇÕES UTILITÁRIAS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_step() {
    echo -e "\n${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}» $1${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}\n"
}

# Confirmar
confirm() {
    if [[ "$FORCE_CLEANUP" == "--force" ]]; then
        return 0
    fi
    
    read -p "$(echo -e ${YELLOW}[?]${NC}) $1 (s/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Ss]$ ]]
}

# Verificar se é root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script deve ser executado como root"
        echo "Use: sudo $0"
        exit 1
    fi
}

# ============================================================================
# LIMPEZA
# ============================================================================

remove_nat_router_service() {
    log_step "Removendo Serviço NAT Router"

    if [[ -f /etc/systemd/system/nat-router.service ]]; then
        log_info "Desabilitando serviço nat-router..."
        systemctl disable nat-router.service 2>/dev/null || true
        systemctl stop nat-router.service 2>/dev/null || true
        rm -f /etc/systemd/system/nat-router.service
        systemctl daemon-reload
        log_success "Serviço removido"
    else
        log_warn "Serviço nat-router não encontrado"
    fi
}

remove_nftables_config() {
    log_step "Removendo Configuração nftables"

    if [[ -f /etc/nftables.conf ]]; then
        log_info "Desabilitando nftables..."
        systemctl stop nftables 2>/dev/null || true
        systemctl disable nftables 2>/dev/null || true
        
        # Restaurar backup se existir
        if [[ -f "$BACKUP_DIR/nftables.conf"* ]]; then
            log_info "Restaurando configuração anterior..."
            cp "$BACKUP_DIR/nftables.conf"* /etc/nftables.conf 2>/dev/null || true
        fi
        
        # Limpar nftables
        nft flush ruleset 2>/dev/null || true
        
        log_success "nftables limpo"
    else
        log_warn "Configuração nftables não encontrada"
    fi
}

remove_dnsmasq_config() {
    log_step "Removendo Configuração dnsmasq"

    if systemctl is-active --quiet dnsmasq; then
        log_info "Parando dnsmasq..."
        systemctl stop dnsmasq
        log_success "dnsmasq parado"
    fi

    if [[ -f /etc/dnsmasq.conf ]]; then
        log_info "Removendo configuração dnsmasq..."
        
        # Restaurar backup se existir
        if [[ -f "$BACKUP_DIR/dnsmasq.conf"* ]]; then
            log_info "Restaurando configuração anterior..."
            cp "$BACKUP_DIR/dnsmasq.conf"* /etc/dnsmasq.conf 2>/dev/null || true
        fi
        
        log_success "Configuração removida"
    fi

    # Desabilitar no boot
    systemctl disable dnsmasq 2>/dev/null || true
}

remove_sysctl_config() {
    log_step "Removendo Configuração sysctl"

    if [[ -f /etc/sysctl.d/30-nat-router.conf ]]; then
        log_info "Removendo arquivo de configuração..."
        rm -f /etc/sysctl.d/30-nat-router.conf
        
        # Recarregar sysctl
        sysctl -p > /dev/null 2>&1 || true
        
        log_success "Configuração sysctl removida"
    else
        log_warn "Configuração sysctl não encontrada"
    fi

    # Restaurar IP forwarding padrão
    log_info "Desabilitando IP forwarding..."
    sysctl -w net.ipv4.ip_forward=0 > /dev/null
    sysctl -w net.ipv6.conf.all.forwarding=0 > /dev/null
    log_success "IP forwarding desabilitado"
}

remove_network_config() {
    log_step "Removendo Configuração de Rede"

    if [[ -f /etc/systemd/network/20-nat-router-*.network ]]; then
        log_info "Removendo arquivo de rede systemd..."
        rm -f /etc/systemd/network/20-nat-router-*.network
        
        # Reiniciar systemd-networkd
        if systemctl is-active --quiet systemd-networkd; then
            systemctl restart systemd-networkd
        fi
        
        log_success "Configuração de rede removida"
    else
        log_warn "Configuração de rede não encontrada"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log_info "╔════════════════════════════════════════════════════╗"
    log_info "║   Arch Linux NAT Router Cleanup Script             ║"
    log_info "║                                                    ║"
    log_info "║   Remove Todas as Configurações NAT Router         ║"
    log_info "╚════════════════════════════════════════════════════╝"

    check_root

    # Definir diretório de backup
    BACKUP_DIR="/root/nat-router-backups"

    # Avisar o usuário
    echo -e "\n${YELLOW}⚠️  AVISO:${NC}"
    echo "Este script irá remover:"
    echo "  • Serviço systemd nat-router"
    echo "  • Configuração nftables"
    echo "  • Configuração dnsmasq"
    echo "  • Configuração sysctl"
    echo "  • Configuração de rede"
    echo ""
    echo "Os backups serão mantidos em: $BACKUP_DIR"
    echo ""

    if ! confirm "Deseja continuar com a limpeza?"; then
        log_warn "Limpeza cancelada"
        exit 0
    fi

    # Executar limpeza
    remove_nat_router_service
    remove_nftables_config
    remove_dnsmasq_config
    remove_sysctl_config
    remove_network_config

    # Resumo
    log_step "Limpeza Concluída"

    echo -e "${CYAN}┌─ RESUMO ──────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} ${GREEN}✓${NC} Todas as configurações NAT Router foram removidas"
    echo -e "${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} ${YELLOW}Backups:${NC}"
    echo -e "${CYAN}│${NC}   Mantidos em: $BACKUP_DIR"
    echo -e "${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} ${YELLOW}Próximas Etapas:${NC}"
    echo -e "${CYAN}│${NC}   • Restart do sistema recomendado"
    echo -e "${CYAN}│${NC}   • sudo systemctl restart networking"
    echo -e "${CYAN}│${NC}   • sudo reboot (recomendado)"
    echo -e "${CYAN}│${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────┘${NC}"

    log_success "Limpeza finalizada"
}

# ============================================================================
# EXECUTAR
# ============================================================================

main "$@"
