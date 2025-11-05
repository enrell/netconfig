# Arch Linux NAT Router

Setup automatizado para transformar um notebook Arch Linux com Wi-Fi em roteador NAT para PC via Ethernet.

## Pré-requisitos

- Arch Linux instalado
- Wi-Fi já conectada e funcionando
- 2 interfaces de rede (1 Ethernet, 1 Wi-Fi)
- Acesso root/sudo

## Setup Inicial

### 1. Configurar Data e Hora

```bash
timedatectl set-timezone America/Sao_Paulo
timedatectl set-ntp true
timedatectl status
```

### 2. Configurar Wi-Fi

**Opção 1: iwctl (recomendado)**

```bash
iwctl
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "SSID"
exit
```

**Opção 2: wpa_supplicant + wpa_cli (alternativa)**

```bash
# Criar arquivo de configuração
cat > /etc/wpa_supplicant/wpa_supplicant.conf <<EOF
ctrl_interface=/run/wpa_supplicant
update_config=1
EOF

# Iniciar wpa_supplicant
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf

# Conectar à rede
wpa_cli
> add_network
> set_network 0 ssid "SSID"
> set_network 0 psk "SENHA"
> set_network 0 key_mgmt WPA-PSK
> enable_network 0
> save_config
> quit

# Obter IP (DHCP)
dhclient wlan0
```

### 3. Clonar Repositório

```bash
git clone https://github.com/enrell/netconfig.git
cd netconfig
chmod +x archlinux-nat-router.sh
```

## Executar

### Listar interfaces disponíveis

```bash
ip link show
```

### Executar (especificar interfaces obrigatório)

```bash
sudo ./archlinux-nat-router.sh <eth_interface> <wlan_interface>
# Exemplo:
sudo ./archlinux-nat-router.sh enp1s0f2 wlan0
```

## Limpar Configurações

```bash
sudo ./cleanup-archlinux-nat-router.sh
```

Com `--force` para pular confirmações:

```bash
sudo ./cleanup-archlinux-nat-router.sh --force
```

## Configurações Padrão

- **Rede LAN:** 10.42.0.0/24
- **Gateway:** 10.42.0.1
- **DHCP:** 10.42.0.10 - 10.42.0.100
- **Persistência:** nenhuma (LiveUSB)

## Conectar PC via Ethernet

1. Plugar cabo Ethernet no PC
2. Configure interface Ethernet com IP da rede LAN:

```bash
# Linux
sudo dhclient eth0
# ou
sudo ip addr add 10.42.0.50/24 dev eth0
sudo ip route add default via 10.42.0.1
```

```bash
# Windows
# Automaticamente via DHCP ou:
ipconfig /all
# Configure manualmente com gateway 10.42.0.1
```

## Troubleshooting

- **Listar interfaces:** `ip link show`
- **Wi-Fi não conecta:** `iwctl station wlan0 show`
- **Testar conectividade:** `ping 10.42.0.1`
- **Status dnsmasq:** `systemctl status dnsmasq`
- **Ver regras firewall:** `nft list ruleset`
- **Logs:** `journalctl -xe`
