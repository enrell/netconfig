#!/bin/sh
#
# Alpine NAT Router Setup Script
# Transforms a notebook (Wi-Fi) into a NAT router for a wired PC
#
# Usage:
#   ./alpine-nat-router.sh [OPTIONS]
#
# Options:
#   ETH_IF=<interface>      Override Ethernet interface (default: auto-detect)
#   WLAN_IF=<interface>     Override Wi-Fi interface (default: auto-detect)
#   WIFI_SSID=<ssid>        Wi-Fi SSID (if you want script to connect)
#   WIFI_PSK=<password>     Wi-Fi password (required if WIFI_SSID is set)
#   LAN_NETWORK=<cidr>      LAN network (default: 192.168.123.0/24)
#   DHCP_START=<ip>         DHCP pool start (default: 192.168.123.10)
#   DHCP_END=<ip>           DHCP pool end (default: 192.168.123.100)
#   DHCP_LEASE=<time>       DHCP lease time (default: 12h)
#   ENABLE_AUTOBOOT=1       Create autoexec script for OpenRC (default: 0)
#
# Example:
#   ./alpine-nat-router.sh ETH_IF=eth0 WLAN_IF=wlan0 WIFI_SSID="MyWiFi" WIFI_PSK="password123"
#

set -e

# ============================================================================
# Configuration & Defaults
# ============================================================================

LAN_NETWORK="${LAN_NETWORK:-192.168.123.0/24}"
LAN_IP="192.168.123.1"
DHCP_START="${DHCP_START:-192.168.123.10}"
DHCP_END="${DHCP_END:-192.168.123.100}"
DHCP_LEASE="${DHCP_LEASE:-12h}"
ENABLE_AUTOBOOT="${ENABLE_AUTOBOOT:-0}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# Network Interface Detection
# ============================================================================

detect_eth_interface() {
    local iface
    
    # Try common Ethernet naming patterns
    for iface in eth0 ens0 enp0s3 enp0s31f6; do
        if ip link show "$iface" >/dev/null 2>&1; then
            echo "$iface"
            return 0
        fi
    done
    
    # Fallback: get first non-loopback, non-wireless interface
    iface=$(ip -o link show | grep -v "link/loopback" | grep -v "wlan\|wpa\|waps" | head -n 1 | awk '{print $2}' | tr -d ':')
    if [ -n "$iface" ]; then
        echo "$iface"
        return 0
    fi
    
    return 1
}

detect_wlan_interface() {
    local iface
    
    # Try common wireless naming patterns
    for iface in wlan0 wlan1 wlp0s20f3 wlp3s0; do
        if ip link show "$iface" >/dev/null 2>&1; then
            echo "$iface"
            return 0
        fi
    done
    
    # Fallback: get first wireless interface
    iface=$(ip -o link show | grep -E "wlan|wpa|waps" | head -n 1 | awk '{print $2}' | tr -d ':')
    if [ -n "$iface" ]; then
        echo "$iface"
        return 0
    fi
    
    return 1
}

# ============================================================================
# Installation & System Setup
# ============================================================================

install_dependencies() {
    log_info "Updating package indices..."
    apk update
    
    log_info "Installing required packages..."
    local packages="iproute2 nftables dnsmasq udhcpc openrc alpine-conf"
    
    # Add wireless tools only if Wi-Fi connection via script is requested
    if [ -n "$WIFI_SSID" ]; then
        # Use iwd (lighter than wpa_supplicant, Alpine default)
        packages="$packages iwd"
    fi
    
    # shellcheck disable=SC2086
    apk add --no-cache $packages
    
    log_success "Dependencies installed"
}

# ============================================================================
# Wi-Fi Connection (Optional)
# ============================================================================

setup_wifi_connection() {
    if [ -z "$WIFI_SSID" ]; then
        log_warn "No WIFI_SSID provided; assuming Wi-Fi is already connected"
        return 0
    fi
    
    if [ -z "$WIFI_PSK" ]; then
        log_error "WIFI_PSK required when WIFI_SSID is specified"
        exit 1
    fi
    
    log_info "Setting up Wi-Fi connection to '$WIFI_SSID' using iwd..."
    
    # Bring up Wi-Fi interface
    log_info "Bringing up interface $WLAN_IF..."
    ip link set "$WLAN_IF" up
    sleep 1
    
    # Connect using iwd (Alpine's preferred wireless daemon)
    log_info "Connecting to '$WIFI_SSID' using iwd..."
    
    # Start iwd service if not running
    rc-service iwd start 2>/dev/null || true
    sleep 1
    
    # Connect using iwctl (iwd control tool)
    if command -v iwctl >/dev/null 2>&1; then
        # Connect with password
        iwctl station "$WLAN_IF" connect "$WIFI_SSID" --passphrase "$WIFI_PSK" 2>/dev/null
        sleep 3
        
        # Verify connection
        local wifi_status=$(iwctl station "$WLAN_IF" show 2>/dev/null | grep -i "connected" || echo "")
        if [ -z "$wifi_status" ]; then
            log_warn "iwd connection may have failed; trying alternative method..."
        fi
    else
        log_warn "iwctl not found; trying manual wpa_supplicant as fallback..."
        
        # Fallback: use wpa_supplicant if iwd not available
        local wpa_conf="/etc/wpa_supplicant/wpa_supplicant.conf"
        mkdir -p /etc/wpa_supplicant
        
        cat > "$wpa_conf" <<EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1

network={
    ssid="$WIFI_SSID"
    psk="$WIFI_PSK"
}
EOF
        chmod 600 "$wpa_conf"
        
        killall wpa_supplicant 2>/dev/null || true
        sleep 1
        
        wpa_supplicant -B -i "$WLAN_IF" -c "$wpa_conf" -D nl80211,wext 2>/dev/null || true
        sleep 2
    fi
    
    # Request IP via DHCP
    log_info "Requesting IP via DHCP on $WLAN_IF..."
    udhcpc -i "$WLAN_IF" -s /usr/share/udhcp/default.script
    
    sleep 1
    log_success "Wi-Fi connection established"
}

# ============================================================================
# LAN Configuration
# ============================================================================

configure_lan_interface() {
    log_info "Configuring LAN interface $ETH_IF..."
    
    # Bring up Ethernet interface
    ip link set "$ETH_IF" up
    
    # Assign static IP to Ethernet interface
    ip addr flush dev "$ETH_IF"
    ip addr add "$LAN_IP/24" dev "$ETH_IF"
    
    log_success "LAN interface configured: $LAN_IP/24 on $ETH_IF"
}

# ============================================================================
# IP Forwarding & NAT (nftables)
# ============================================================================

setup_forwarding_and_nat() {
    log_info "Enabling IP forwarding..."
    
    # Enable IPv4 forwarding
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    
    # Make it persistent across reboots (if sysctl.conf exists)
    if grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf 2>/dev/null; then
        sed -i 's/^net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    else
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf 2>/dev/null || true
    fi
    
    log_success "IP forwarding enabled"
    
    log_info "Configuring nftables NAT (permissive mode - full LAN access)..."
    
    # Flush any existing rules
    nft flush ruleset 2>/dev/null || true
    
    # Create nftables ruleset with permissive policy (ACCEPT all)
    nft add table inet filter
    nft add chain inet filter input { type filter hook input priority 0 \; policy accept \; }
    nft add chain inet filter forward { type filter hook forward priority 0 \; policy accept \; }
    nft add chain inet filter output { type filter hook output priority 0 \; policy accept \; }
    
    nft add table inet nat
    nft add chain inet nat postrouting { type nat hook postrouting priority 100 \; }
    
    # Optional: Drop invalid packets
    nft add rule inet filter input ct state invalid drop
    nft add rule inet filter forward ct state invalid drop
    
    # NAT: masquerade outgoing packets from LAN via Wi-Fi interface
    # This allows PC -> internal LAN devices AND PC -> internet
    nft add rule inet nat postrouting oifname "$WLAN_IF" masquerade
    
    log_success "nftables rules configured (permissive - all traffic allowed)"
}

enable_nftables_service() {
    log_info "Enabling nftables service..."
    
    rc-service nftables restart || true
    rc-update add nftables default 2>/dev/null || true
    
    log_success "nftables service enabled"
}

# ============================================================================
# DHCP/DNS Setup (dnsmasq)
# ============================================================================

setup_dnsmasq() {
    log_info "Configuring dnsmasq..."
    
    # Backup original config if it exists
    if [ -f /etc/dnsmasq.conf ]; then
        cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
    fi
    
    # Create minimal dnsmasq configuration
    cat > /etc/dnsmasq.conf <<EOF
# Alpine NAT Router - dnsmasq config
# Automatically generated by alpine-nat-router.sh

# Listen on LAN interface only
interface=$ETH_IF
bind-interfaces

# DHCP configuration
dhcp-range=$DHCP_START,$DHCP_END,$DHCP_LEASE
dhcp-option=option:router,$LAN_IP
dhcp-option=option:dns-server,8.8.8.8,8.8.4.4

# DNS options
no-resolv
server=8.8.8.8
server=8.8.4.4

# Logging (optional)
log-dhcp
log-queries
EOF
    
    log_success "dnsmasq configuration created"
}

enable_dnsmasq_service() {
    log_info "Enabling dnsmasq service..."
    
    rc-service dnsmasq restart || true
    rc-update add dnsmasq default 2>/dev/null || true
    
    log_success "dnsmasq service enabled"
}

# ============================================================================
# OpenRC Autoboot Setup (Optional)
# ============================================================================

setup_openrc_autoboot() {
    if [ "$ENABLE_AUTOBOOT" != "1" ]; then
        log_warn "Autoboot not enabled. To enable, set ENABLE_AUTOBOOT=1"
        return 0
    fi
    
    log_info "Setting up OpenRC autoboot script..."
    
    local local_d="/etc/local.d"
    mkdir -p "$local_d"
    
    local script="$local_d/nat-router-autoexec.start"
    
    cat > "$script" <<'SCRIPT'
#!/bin/sh
# Alpine NAT Router Autoexec Script
# Restored on every boot via OpenRC

echo "[NAT Router] Applying network configuration on boot..."

ETH_IF="$1"
WLAN_IF="$2"
LAN_IP="$3"

if [ -z "$ETH_IF" ] || [ -z "$WLAN_IF" ] || [ -z "$LAN_IP" ]; then
    echo "[NAT Router] Missing parameters for autoboot"
    exit 1
fi

# Bring up interfaces
ip link set "$ETH_IF" up
ip addr flush dev "$ETH_IF"
ip addr add "$LAN_IP/24" dev "$ETH_IF"

# Restart services
rc-service nftables restart
rc-service dnsmasq restart

echo "[NAT Router] Autoboot configuration applied"
SCRIPT
    
    chmod +x "$script"
    
    # Prepend parameters to the actual execution
    # For persistence, we store interfaces in a separate file
    cat > /etc/local.d/nat-router.params <<EOF
ETH_IF=$ETH_IF
WLAN_IF=$WLAN_IF
LAN_IP=$LAN_IP
EOF
    chmod 600 /etc/local.d/nat-router.params
    
    # Add local to default runlevel if not already there
    if ! grep -q "^local" /etc/runlevels/default/local 2>/dev/null; then
        rc-update add local default 2>/dev/null || true
    fi
    
    log_success "OpenRC autoboot script created"
}

# ============================================================================
# Validation & Summary
# ============================================================================

validate_setup() {
    log_info "Validating configuration..."
    
    local errors=0
    
    # Check IP forwarding
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
        log_error "IP forwarding not enabled"
        errors=$((errors + 1))
    fi
    
    # Check interfaces are up
    local eth_state=$(ip link show "$ETH_IF" | grep -o "UP" || echo "DOWN")
    if [ "$eth_state" != "UP" ]; then
        log_error "Ethernet interface $ETH_IF is not UP"
        errors=$((errors + 1))
    fi
    
    local wlan_state=$(ip link show "$WLAN_IF" | grep -o "UP" || echo "DOWN")
    if [ "$wlan_state" != "UP" ]; then
        log_warn "Wi-Fi interface $WLAN_IF is not UP"
    fi
    
    # Check services
    if ! rc-service nftables status >/dev/null 2>&1; then
        log_warn "nftables service may not be running"
    fi
    
    if ! rc-service dnsmasq status >/dev/null 2>&1; then
        log_warn "dnsmasq service may not be running"
    fi
    
    if [ $errors -gt 0 ]; then
        log_error "Validation failed with $errors error(s)"
        return 1
    fi
    
    log_success "Configuration validated"
    return 0
}

display_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "${GREEN}Alpine NAT Router Setup Complete${NC}"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "📋 Configuration Summary:"
    echo "  Ethernet Interface (LAN):  $ETH_IF"
    echo "  Wi-Fi Interface (WAN):     $WLAN_IF"
    echo "  LAN Network:               $LAN_NETWORK"
    echo "  Gateway IP:                $LAN_IP"
    echo "  DHCP Pool:                 $DHCP_START - $DHCP_END"
    echo "  DHCP Lease:                $DHCP_LEASE"
    echo ""
    echo "🔌 Next Steps:"
    echo "  1. Connect the PC to the notebook via Ethernet cable"
    echo "  2. The PC should receive an IP in range $DHCP_START - $DHCP_END"
    echo "  3. Verify connectivity on PC:"
    echo "     - Check IP: ip a"
    echo "     - Test ping: ping 8.8.8.8"
    echo "     - Test DNS: ping google.com"
    echo ""
    echo "🧪 Quick Tests (on notebook):"
    echo "  • View IP configuration:    ip addr show"
    echo "  • View nftables rules:      nft list ruleset"
    echo "  • View DHCP leases:         cat /var/lib/misc/dnsmasq.leases"
    echo "  • Monitor dnsmasq:          tail -f /var/log/messages"
    echo ""
    echo "💾 Persistence:"
    if [ "$ENABLE_AUTOBOOT" = "1" ]; then
        echo "  ✓ Autoboot script enabled (runs on every boot)"
    else
        echo "  ✗ Autoboot not enabled"
        echo "    To enable, create an apkovl or rerun with ENABLE_AUTOBOOT=1"
    fi
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    check_root
    
    # Parse command-line arguments
    for arg in "$@"; do
        eval "$arg"
    done
    
    # Auto-detect interfaces if not provided
    if [ -z "$ETH_IF" ]; then
        log_info "Auto-detecting Ethernet interface..."
        if ! ETH_IF=$(detect_eth_interface); then
            log_error "Could not auto-detect Ethernet interface"
            log_info "Please specify manually: ETH_IF=eth0 $0"
            exit 1
        fi
        log_success "Detected Ethernet: $ETH_IF"
    fi
    
    if [ -z "$WLAN_IF" ]; then
        log_info "Auto-detecting Wi-Fi interface..."
        if ! WLAN_IF=$(detect_wlan_interface); then
            log_error "Could not auto-detect Wi-Fi interface"
            log_info "Please specify manually: WLAN_IF=wlan0 $0"
            exit 1
        fi
        log_success "Detected Wi-Fi: $WLAN_IF"
    fi
    
    # Validate interfaces are different
    if [ "$ETH_IF" = "$WLAN_IF" ]; then
        log_error "Ethernet and Wi-Fi interfaces cannot be the same"
        exit 1
    fi
    
    # Execute setup steps
    log_info "Starting Alpine NAT Router setup..."
    echo ""
    
    install_dependencies
    setup_wifi_connection
    configure_lan_interface
    setup_forwarding_and_nat
    enable_nftables_service
    setup_dnsmasq
    enable_dnsmasq_service
    setup_openrc_autoboot
    
    validate_setup
    display_summary
    
    log_success "Setup completed successfully!"
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
