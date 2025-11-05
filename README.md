# Alpine NAT Router Setup Script

Transforma um notebook Alpine Linux (com Wi-Fi) em um **roteador NAT** com acesso completo à LAN para um PC ligado via cabo Ethernet.

## Objetivo

Quando você inicializa o Alpine "standard" no notebook e executa este script, o PC recebe automaticamente um IP via DHCP na porta Ethernet do notebook e pode:
- ✅ Navegar na **internet** através do notebook
- ✅ Acessar **qualquer dispositivo da LAN** (Wi-Fi do roteador)
- ✅ Comunicar **bidirecionalmente** com todos os dispositivos da rede

Toda a configuração de **forwarding**, **NAT**, **firewall** (permissivo) e **DHCP** é feita automaticamente.

## Fluxo de Rede

```
         Home Network (Wi-Fi do roteador)
         │192.168.1.0/24 (exemplo)
         │
    ┌────┴────────────────────────────────┐
    │      Roteador Wi-Fi                  │
    │  (ex: gateway 192.168.1.1)           │
    └────┬────────────────────────────────┘
         │ Wi-Fi
         │
    ┌────┴─────────────────────────────────────────┐
    │  Notebook (Alpine)                           │
    ├─────────────────────────────────────────────┤
    │  ┌──────────────────┐  ┌─────────────────┐ │
    │  │  Wi-Fi (wlan0)   │  │ Ethernet (eth0) │ │
    │  │ 192.168.1.x/24   │  │ 192.168.123.1   │ │
    │  │ (DHCP from GW)   │  │ (router)        │ │
    │  └──────────────────┘  └─────────────────┘ │
    └────┬─────────────────────────────────┬─────┘
         │ (NAT + Forward)                 │ Ethernet
         │                                 │
    [Home LAN                          ┌───┴──────────┐
     Devices]                          │   PC         │
                                       │ 192.168.123.x│
                                       │(DHCP)        │
                                       └──────────────┘
```

**Tráfego permitido:**
- PC → Internet: `PC → Notebook (NAT) → Roteador Wi-Fi → Internet`
- PC → LAN Device: `PC → Notebook (Forward) → Roteador Wi-Fi → Device`
- LAN Device → PC: `Device → Roteador Wi-Fi → Notebook (Forward) → PC` (sem restrições)

## O que o Script Faz

### 1. **Instala Dependências**
- `iproute2` — configuração de rede avançada
- `nftables` — firewall moderno e NAT
- `dnsmasq` — DHCP e DNS
- `udhcpc` — cliente DHCP (para conectar ao Wi-Fi)
- `wpa_supplicant`, `wireless-tools` — (se conectar ao Wi-Fi via script)
- `openrc` — init system (para serviços)

### 2. **Detecta Interfaces de Rede**
- Detecta automaticamente `eth0` (Ethernet) e `wlan0` (Wi-Fi)
- Permite especificar manualmente se necessário

### 3. **(Opcional) Conecta ao Wi-Fi**
- Se você fornecer `WIFI_SSID` e `WIFI_PSK`, o script:
  - Gera configuração do `wpa_supplicant`
  - Inicia o daemon de Wi-Fi
  - Solicita IP ao roteador via DHCP
- Caso contrário, assume que já está conectado por outro método

### 4. **Configura LAN no Cabo**
- Sobe a interface Ethernet
- Atribui IP fixo: `192.168.123.1/24` (configurável)

### 5. **Habilita Roteamento IP e NAT**
- Liga `net.ipv4.ip_forward`
- Cria regras de firewall com `nftables` **(modo permissivo)**:
  - **Política padrão:** ACCEPT (permite todo tráfego)
  - **Apenas descarta:** pacotes inválidos (ct state invalid)
  - **NAT Postrouting:** faz masquerade (NAT) dos pacotes saindo pelo Wi-Fi

**Resultado:** PC tem acesso irrestrito a:
  - Internet (via NAT através do Wi-Fi)
  - Todos os dispositivos na LAN (Wi-Fi do roteador)
  - Bidirecional: dispositivos da LAN também podem acessar o PC

### 6. **Ativa DHCP/DNS (dnsmasq)**
- Cria configuração mínima para escutar na Ethernet
- Define pool DHCP: `192.168.123.10 - 192.168.123.100` (configurável)
- Reinicia e habilita o serviço

### 7. **(Opcional) Autoexec no Boot**
- Cria script `/etc/local.d/nat-router-autoexec.start`
- Reaplica IP na LAN e reinicia serviços a cada boot
- Ativa `local` runlevel no OpenRC

### 8. **Exibe Sumário e Dicas**
- Confirma interfaces usadas
- Mostra como testar conectividade
- Dicas de troubleshooting

## Instalação

### Copiar para o Notebook

```bash
scp alpine-nat-router.sh root@<notebook-ip>:/root/
ssh root@<notebook-ip>
chmod +x /root/alpine-nat-router.sh
```

Ou simplesmente:

```bash
# Download direto (se estiver em um servidor)
wget https://example.com/alpine-nat-router.sh -O /root/alpine-nat-router.sh
chmod +x /root/alpine-nat-router.sh
```

## Uso

### Uso Simples (Auto-detect)

```bash
./alpine-nat-router.sh
```

O script detecta automaticamente as interfaces. Se o Wi-Fi **já estiver conectado**, tudo funciona direto.

### Com Conexão Wi-Fi Automática

Se você quer que o script conecte ao Wi-Fi durante a execução:

```bash
./alpine-nat-router.sh \
  WIFI_SSID="MyNetwork" \
  WIFI_PSK="mypassword123"
```

### Especificar Interfaces Manualmente

```bash
./alpine-nat-router.sh \
  ETH_IF=eth0 \
  WLAN_IF=wlan0 \
  WIFI_SSID="MyNetwork" \
  WIFI_PSK="mypassword123"
```

### Com Autoboot e Rede Customizada

```bash
./alpine-nat-router.sh \
  ETH_IF=eth0 \
  WLAN_IF=wlan0 \
  LAN_NETWORK="192.168.100.0/24" \
  DHCP_START="192.168.100.10" \
  DHCP_END="192.168.100.200" \
  DHCP_LEASE="24h" \
  ENABLE_AUTOBOOT=1
```

## Variáveis de Configuração

| Variável | Default | Descrição |
|----------|---------|-----------|
| `ETH_IF` | auto-detect | Interface Ethernet (LAN) |
| `WLAN_IF` | auto-detect | Interface Wi-Fi (WAN) |
| `WIFI_SSID` | (vazio) | SSID do Wi-Fi (opcional) |
| `WIFI_PSK` | (vazio) | Senha Wi-Fi (necessário se `WIFI_SSID` for set) |
| `LAN_NETWORK` | `192.168.123.0/24` | Rede LAN do cabo |
| `DHCP_START` | `192.168.123.10` | Primeiro IP do pool DHCP |
| `DHCP_END` | `192.168.123.100` | Último IP do pool DHCP |
| `DHCP_LEASE` | `12h` | Tempo de concessão DHCP |
| `ENABLE_AUTOBOOT` | `0` | Habilitar autoexec no OpenRC (1 = sim) |

## Teste de Funcionamento

### No Notebook

```bash
# 1. Ver configuração de IP
ip addr show

# 2. Ver regras de firewall
nft list ruleset

# 3. Ver leases DHCP concedidas
cat /var/lib/misc/dnsmasq.leases

# 4. Monitorar dnsmasq (logs)
tail -f /var/log/messages

# 5. Ver interfaces ativas
ip link show
```

### No PC (conectado via cabo)

```bash
# 1. Solicitar IP via DHCP (Linux)
dhclient eth0
# ou (Alpine)
udhcpc -i eth0

# 2. Verificar IP recebido
ip addr show

# 3. Testar conectividade interna (gateway do notebook)
ping 192.168.123.1

# 4. Testar acesso a dispositivos na LAN (via notebook)
# Exemplo: pingue o roteador Wi-Fi
ping 192.168.1.1

# 5. Descobrir outro dispositivo na LAN e testar
# Exemplo: servidor local, impressora, etc
ping 192.168.1.100

# 6. Testar conectividade externa
ping 8.8.8.8

# 7. Testar resolução DNS
ping google.com
nslookup google.com
```

### No Roteador/Dispositivos da LAN

```bash
# Testar acesso ao PC (configurado no notebook)
ping 192.168.123.1  # gateway do notebook
# ou direto ao PC (se souber o IP da LAN)
ping 192.168.123.x

# Exemplo em outro dispositivo Linux conectado ao Wi-Fi:
# Se o PC recebeu IP 192.168.123.50
ping 192.168.123.50
```

## Troubleshooting

### PC não recebe IP via DHCP

1. Verificar se `dnsmasq` está rodando:
   ```bash
   rc-service dnsmasq status
   ```

2. Reiniciar `dnsmasq`:
   ```bash
   rc-service dnsmasq restart
   ```

3. Ver logs:
   ```bash
   tail -f /var/log/messages | grep dnsmasq
   ```

### PC recebe IP mas não tem internet ou não consegue acessar LAN

1. Verificar se `nftables` está ativo:
   ```bash
   nft list ruleset
   ```

2. Verificar se IP forwarding está habilitado:
   ```bash
   cat /proc/sys/net/ipv4/ip_forward
   # Deve ser 1
   ```

3. Testar conectividade local (ao notebook):
   ```bash
   ping 192.168.123.1  # gateway
   ```

4. Testar conectividade à LAN (via notebook):
   ```bash
   ping 192.168.1.1    # roteador Wi-Fi (exemplo)
   ```

5. Ver tráfego:
   ```bash
   tcpdump -i eth0 -n  # tráfego do PC
   tcpdump -i wlan0 -n # tráfego para fora
   ```

### Dispositivos da LAN não conseguem acessar o PC

1. Verificar que o PC recebeu IP DHCP:
   ```bash
   # No notebook
   cat /var/lib/misc/dnsmasq.leases
   ```

2. Verificar se `nftables` permite tráfego inverso:
   ```bash
   # No notebook
   nft list ruleset
   # Deve mostrar policy accept no forward chain
   ```

3. Testar ping do roteador/outro device:
   ```bash
   # De outro device na LAN
   ping 192.168.123.x  # IP do PC (descubra com dnsmasq.leases)
   ```

4. Se falhar, verificar no notebook se há bloqueios:
   ```bash
   tcpdump -i wlan0 -n | grep 192.168.123  # ver pacotes chegando
   tcpdump -i eth0 -n | grep 192.168.1     # ver resposta saindo
   ```

### Interface Wi-Fi não conecta

1. Verificar se `wpa_supplicant` está rodando:
   ```bash
   ps aux | grep wpa_supplicant
   ```

2. Verificar status:
   ```bash
   wpa_cli -i wlan0 status
   ```

3. Reconectar manualmente:
   ```bash
   killall wpa_supplicant
   ./alpine-nat-router.sh WIFI_SSID="..." WIFI_PSK="..."
   ```

## Modo de Firewall (Permissivo)

Este script usa uma **política de firewall permissiva** (ACCEPT) por padrão, o que significa:

### ✅ O que é permitido:
- ✅ PC → Internet (através do NAT)
- ✅ PC → Qualquer dispositivo na LAN do roteador
- ✅ Qualquer dispositivo da LAN → PC
- ✅ Todo tráfego bidirecional entre as subnets
- ✅ Tráfego local e roteado sem restrições

### 🛡️ O que é bloqueado:
- ❌ Apenas pacotes com estado inválido (`ct state invalid`) são descartados
- Tudo o mais é permitido

### Por que modo permissivo?
O objetivo é permitir acesso **completo e irrestrito** da LAN ao PC. Se você precisar de um firewall mais restritivo, veja a seção **Customização** no arquivo `CONFIGURATION.md` para exemplos de regras mais rigorosas.

### Exemplo de acesso esperado:

```plaintext
PC (192.168.123.50)
├─ Acessa Internet           → ✅ Funciona via NAT
├─ Acessa Roteador (192.168.1.1)  → ✅ Funciona via Forward
├─ Acessa TV (192.168.1.50)       → ✅ Funciona via Forward
├─ Acessa NAS (192.168.1.100)     → ✅ Funciona via Forward
└─ Acessa Notebook (192.168.123.1) → ✅ Funciona localmente

Notebook (192.168.123.1)
└─ Acessa PC (192.168.123.50)     → ✅ Funciona localmente

Roteador (192.168.1.1) / Qualquer device LAN
└─ Acessa PC (192.168.123.50)     → ✅ Funciona via Forward do notebook
```

## Persistência (Tornar Permanente)

O Alpine padrão roda da RAM. Para fazer as configurações **persistirem** entre reboots:

### Opção 1: Usar o autoboot (recomendado)

```bash
./alpine-nat-router.sh ENABLE_AUTOBOOT=1
```

Isso cria um script que roda automaticamente a cada boot. **Nota:** ainda assim, a sessão será reiniciada da RAM; apenas as configurações de rede serão rereaplicadas.

### Opção 2: Criar um apkovl (Overlay)

Para persistência real, crie um arquivo de overlay Alpine (`.apkovl`):

```bash
# Na primeira execução com autoboot
./alpine-nat-router.sh ENABLE_AUTOBOOT=1

# Depois, criar o overlay
tar -czf /media/usb/alpine-usbkey.apkovl.tar.gz \
  -C / \
  etc/dnsmasq.conf \
  etc/sysctl.conf \
  etc/local.d/nat-router-autoexec.start \
  etc/local.d/nat-router.params

# Copiar para mídia de boot
cp /media/usb/alpine-usbkey.apkovl.tar.gz /media/usb/
```

## Exemplo Completo de Uso

```bash
#!/bin/sh
# Script executado no notebook Alpine

# 1. Baixar o script
wget https://example.com/alpine-nat-router.sh -O /root/setup.sh
chmod +x /root/setup.sh

# 2. Executar com as suas credenciais Wi-Fi
/root/setup.sh \
  WIFI_SSID="MyHomeNetwork" \
  WIFI_PSK="secure_password" \
  LAN_NETWORK="192.168.100.0/24" \
  ENABLE_AUTOBOOT=1

# 3. Ao final, conectar o PC via cabo e testar
# No PC:
# $ dhclient eth0
# $ ping google.com
```

## Arquivos Criados/Modificados

- `/etc/dnsmasq.conf` — configuração DHCP/DNS
- `/etc/sysctl.conf` — IP forwarding
- `/etc/wpa_supplicant/wpa_supplicant.conf` — credenciais Wi-Fi (se aplicável)
- `/etc/local.d/nat-router-autoexec.start` — script de autoboot (se `ENABLE_AUTOBOOT=1`)
- `/etc/local.d/nat-router.params` — parâmetros persistentes (se autoboot)

## Restaurar Configuração Original

```bash
# Restaurar dnsmasq
mv /etc/dnsmasq.conf.bak /etc/dnsmasq.conf

# Desabilitar serviços
rc-update del nftables default
rc-update del dnsmasq default
rc-update del local default

# Reiniciar
reboot
```

## Requisitos

- Alpine Linux (testado em edge, mas compatível com versões LTS)
- Acesso root
- Duas interfaces de rede (Ethernet + Wi-Fi)
- Conexão Wi-Fi já ativa (ou credenciais para script conectar)

## Logs & Debugging

Todos os passos são loggados com cores para fácil leitura:

- 🟦 **[INFO]** — informações gerais
- 🟩 **[OK]** — sucesso
- 🟨 **[WARN]** — avisos
- 🟥 **[ERROR]** — erros críticos

## Licença

Este script é fornecido como está, sem garantias. Use por sua conta e risco.

---

**Desenvolvido para Alpine Linux | NAT Router Setup**
