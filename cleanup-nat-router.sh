#!/bin/sh
#
# Alpine NAT Router Cleanup Script
# Removes all NAT router configuration and restores original state
#
# Usage: ./cleanup-nat-router.sh [OPTIONS]
#

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FORCE="${FORCE:-0}"

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo "${RED}[ERROR]${NC} $*" >&2
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

confirm_action() {
    local prompt="$1"
    local response
    
    if [ "$FORCE" = "1" ]; then
        return 0
    fi
    
    printf "%s${YELLOW}%s${NC} (yes/no): " "$prompt" " [CONFIRM]"
    read -r response
    
    case "$response" in
        yes|YES|y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================================
# Service Cleanup
# ============================================================================

stop_services() {
    log_info "Stopping services..."
    
    if rc-service nftables status >/dev/null 2>&1; then
        log_info "Stopping nftables..."
        rc-service nftables stop || true
    fi
    
    if rc-service dnsmasq status >/dev/null 2>&1; then
        log_info "Stopping dnsmasq..."
        rc-service dnsmasq stop || true
    fi
    
    log_success "Services stopped"
}

disable_autostart() {
    log_info "Disabling services from autostart..."
    
    rc-update del nftables default 2>/dev/null || true
    rc-update del dnsmasq default 2>/dev/null || true
    rc-update del local default 2>/dev/null || true
    
    log_success "Services disabled from autostart"
}

# ============================================================================
# Configuration Cleanup
# ============================================================================

cleanup_dnsmasq() {
    log_info "Cleaning up dnsmasq configuration..."
    
    if [ -f /etc/dnsmasq.conf ]; then
        log_warn "Removing /etc/dnsmasq.conf"
        rm -f /etc/dnsmasq.conf
    fi
    
    if [ -f /etc/dnsmasq.conf.bak ]; then
        log_info "Restoring backup /etc/dnsmasq.conf.bak"
        mv /etc/dnsmasq.conf.bak /etc/dnsmasq.conf
        log_success "dnsmasq configuration restored"
    else
        log_warn "No backup found; dnsmasq will use default config"
    fi
}

cleanup_nftables() {
    log_info "Cleaning up nftables rules..."
    
    # Flush all rules
    nft flush ruleset 2>/dev/null || log_warn "Could not flush nftables (may already be empty)"
    
    log_success "nftables rules flushed"
}

cleanup_sysctl() {
    log_info "Cleaning up sysctl configuration..."
    
    if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        log_info "Disabling IP forwarding in sysctl.conf..."
        sed -i 's/^net.ipv4.ip_forward=1/net.ipv4.ip_forward=0/' /etc/sysctl.conf
    fi
    
    # Apply changes
    sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1 || true
    
    log_success "IP forwarding disabled"
}

cleanup_wifi() {
    log_info "Cleaning up Wi-Fi configuration..."
    
    if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
        log_warn "Removing /etc/wpa_supplicant/wpa_supplicant.conf"
        rm -f /etc/wpa_supplicant/wpa_supplicant.conf
    fi
    
    # Kill wpa_supplicant if running
    killall wpa_supplicant 2>/dev/null || true
    sleep 1
    
    log_success "Wi-Fi cleanup complete"
}

cleanup_openrc() {
    log_info "Cleaning up OpenRC autoboot scripts..."
    
    if [ -f /etc/local.d/nat-router-autoexec.start ]; then
        log_warn "Removing /etc/local.d/nat-router-autoexec.start"
        rm -f /etc/local.d/nat-router-autoexec.start
    fi
    
    if [ -f /etc/local.d/nat-router.params ]; then
        log_warn "Removing /etc/local.d/nat-router.params"
        rm -f /etc/local.d/nat-router.params
    fi
    
    log_success "OpenRC scripts removed"
}

# ============================================================================
# Interface Cleanup
# ============================================================================

cleanup_interfaces() {
    local eth_if="${1:-eth0}"
    local wlan_if="${2:-wlan0}"
    
    log_info "Resetting network interfaces..."
    
    log_info "Flushing IPs from $eth_if..."
    ip addr flush dev "$eth_if" 2>/dev/null || true
    
    log_info "Bringing down $eth_if..."
    ip link set "$eth_if" down 2>/dev/null || true
    
    log_success "Network interfaces reset"
}

# ============================================================================
# Verification
# ============================================================================

verify_cleanup() {
    local errors=0
    
    echo ""
    echo "${BLUE}══════════════════════════════════════════════════════${NC}"
    echo "${BLUE}Verifying Cleanup${NC}"
    echo "${BLUE}══════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Check IP forwarding
    local forward=$(cat /proc/sys/net/ipv4/ip_forward)
    if [ "$forward" = "0" ]; then
        log_success "IP forwarding disabled"
    else
        log_warn "IP forwarding still enabled (value: $forward)"
    fi
    
    # Check nftables rules
    local rules=$(nft list ruleset 2>/dev/null | wc -l)
    if [ "$rules" -lt 2 ]; then
        log_success "nftables rules flushed"
    else
        log_warn "nftables still has rules ($rules lines)"
    fi
    
    # Check dnsmasq config
    if [ ! -f /etc/dnsmasq.conf ]; then
        log_success "dnsmasq configuration removed"
    else
        log_warn "dnsmasq configuration still exists"
    fi
    
    # Check autoboot scripts
    if [ ! -f /etc/local.d/nat-router-autoexec.start ]; then
        log_success "Autoboot script removed"
    else
        log_warn "Autoboot script still exists"
    fi
    
    # Check services
    if ! rc-update show default 2>/dev/null | grep -q nftables; then
        log_success "nftables removed from autostart"
    else
        log_warn "nftables still in autostart"
        errors=$((errors + 1))
    fi
    
    if ! rc-update show default 2>/dev/null | grep -q dnsmasq; then
        log_success "dnsmasq removed from autostart"
    else
        log_warn "dnsmasq still in autostart"
        errors=$((errors + 1))
    fi
    
    echo ""
    
    if [ $errors -eq 0 ]; then
        log_success "Cleanup verified successfully"
        return 0
    else
        log_warn "Some items were not fully cleaned (check above)"
        return 0
    fi
}

# ============================================================================
# Display Summary
# ============================================================================

display_summary() {
    echo ""
    echo "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo "${GREEN}║   Alpine NAT Router - Cleanup Complete             ║${NC}"
    echo "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Actions taken:"
    echo "  ✓ Stopped nftables service"
    echo "  ✓ Stopped dnsmasq service"
    echo "  ✓ Removed services from autostart"
    echo "  ✓ Cleared nftables rules"
    echo "  ✓ Disabled IP forwarding"
    echo "  ✓ Removed dnsmasq configuration"
    echo "  ✓ Removed Wi-Fi configuration"
    echo "  ✓ Removed autoboot scripts"
    echo ""
    echo "Your Alpine system is back to its original state."
    echo ""
    echo "Notes:"
    echo "  • Network interfaces will need to be reconfigured manually"
    echo "  • To restore the PC connection, run the setup script again"
    echo "  • Any saved backups (.bak files) have been preserved"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    check_root
    
    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --force) FORCE=1 ;;
            ETH_IF=*) ETH_IF="${arg#*=}" ;;
            WLAN_IF=*) WLAN_IF="${arg#*=}" ;;
        esac
    done
    
    ETH_IF="${ETH_IF:-eth0}"
    WLAN_IF="${WLAN_IF:-wlan0}"
    
    echo ""
    echo "${RED}╔════════════════════════════════════════════════════╗${NC}"
    echo "${RED}║   Alpine NAT Router - Cleanup Script                ║${NC}"
    echo "${RED}║   This will remove ALL NAT router configuration    ║${NC}"
    echo "${RED}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This script will:"
    echo "  • Stop nftables and dnsmasq services"
    echo "  • Remove them from autostart"
    echo "  • Delete nftables rules"
    echo "  • Disable IP forwarding"
    echo "  • Remove dnsmasq configuration"
    echo "  • Delete Wi-Fi configuration"
    echo "  • Remove OpenRC autoboot scripts"
    echo ""
    echo "Your system will return to its original state."
    echo ""
    
    # Confirm action
    if ! confirm_action "Do you want to proceed?"; then
        log_warn "Cleanup cancelled"
        exit 0
    fi
    
    echo ""
    log_info "Starting cleanup..."
    echo ""
    
    # Execute cleanup steps
    stop_services
    disable_autostart
    cleanup_nftables
    cleanup_sysctl
    cleanup_dnsmasq
    cleanup_wifi
    cleanup_openrc
    cleanup_interfaces "$ETH_IF" "$WLAN_IF"
    
    # Verify
    verify_cleanup
    
    # Summary
    display_summary
    
    log_success "Cleanup completed!"
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
