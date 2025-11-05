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

```bash
nmcli device wifi list
nmcli device wifi connect "SSID" password "SENHA"
nmcli connection show
```

### 3. Clonar Repositório

```bash
git clone https://github.com/enrell/netconfig.git
cd netconfig
chmod +x archlinux-nat-router.sh
```

## Executar

### Auto-detect (recomendado)

```bash
sudo ./archlinux-nat-router.sh
```

### Especificar interfaces manualmente

```bash
sudo ./archlinux-nat-router.sh enp3s0 wlp4s0
```

### Com autoboot via systemd

```bash
sudo ./archlinux-nat-router.sh enp3s0 wlp4s0 1
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

- **Rede LAN:** 192.168.123.0/24
- **Gateway:** 192.168.123.1
- **DHCP:** 192.168.123.10 - 192.168.123.100
- **Backup:** `/root/nat-router-backups`

## Conectar PC via Ethernet

1. Plugar cabo Ethernet no PC
2. Configure interface Ethernet com IP da rede LAN:

```bash
# Linux
sudo dhclient eth0
# ou
sudo ip addr add 192.168.123.50/24 dev eth0
sudo ip route add default via 192.168.123.1
```

```bash
# Windows
# Automaticamente via DHCP ou:
ipconfig /all
# Configure manualmente com gateway 192.168.123.1
```

## Troubleshooting

- **Wi-Fi não conecta:** `nmcli connection show`
- **Ver interfaces:** `ip link show`
- **Testar conectividade:** `ping 192.168.123.1`
- **Logs:** `sudo journalctl -xe`
