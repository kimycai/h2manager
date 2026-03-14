#!/bin/sh
# hysteria-manager.sh
# description: official Hysteria 2 installation, uninstallation, and configuration wizard

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check root
if [ "$(id -u)" -ne 0 ]; then
  printf "${RED}Please run as root${NC}\n"
  exit 1
fi

show_menu() {
    clear
    printf "${CYAN}=================================${NC}\n"
    printf "${CYAN}   Hysteria 2 Manager Script     ${NC}\n"
    printf "${CYAN}=================================${NC}\n"
    printf "1. Install Hysteria 2\n"
    printf "2. Uninstall Hysteria 2\n"
    printf "3. Configure Hysteria 2 (Wizard)\n"
    printf "4. Start Service\n"
    printf "5. Stop Service\n"
    printf "6. Restart Service\n"
    printf "7. View Status\n"
    printf "0. Exit\n"
    printf "${CYAN}=================================${NC}\n"
    printf "Enter your choice: "
    read choice
    case $choice in
        1) install_hysteria ;;
        2) uninstall_hysteria ;;
        3) configure_hysteria ;;
        4) systemctl start hysteria-server && printf "${GREEN}Service started.${NC}\n" ; printf "Press Enter to return..." ; read dummy ;;
        5) systemctl stop hysteria-server && printf "${YELLOW}Service stopped.${NC}\n" ; printf "Press Enter to return..." ; read dummy ;;
        6) systemctl restart hysteria-server && printf "${GREEN}Service restarted.${NC}\n" ; printf "Press Enter to return..." ; read dummy ;;
        7) systemctl status hysteria-server ; printf "Press Enter to return..." ; read dummy ;;
        0) exit 0 ;;
        *) printf "${RED}Invalid option${NC}\n"; sleep 1 ;;
    esac
}

install_hysteria() {
    printf "${GREEN}Starting official Hysteria 2 installation...${NC}\n"
    curl -fsSL https://get.hy2.sh/ | bash
    printf "${GREEN}Installation completed.${NC}\n"
    printf "Press Enter to return to menu..."
    read dummy
}

uninstall_hysteria() {
    printf "${YELLOW}WARNING: This will remove Hysteria 2 from your system.${NC}\n"
    printf "Are you sure? [y/N]: "
    read confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        systemctl stop hysteria-server
        systemctl disable hysteria-server
        rm -f /etc/systemd/system/hysteria-server.service
        rm -f /etc/systemd/system/hysteria-server@.service
        systemctl daemon-reload
        rm -f /usr/local/bin/hysteria
        printf "Do you want to remove configuration files (/etc/hysteria)? [y/N]: "
        read rm_config
        if [ "$rm_config" = "y" ] || [ "$rm_config" = "Y" ]; then
            rm -rf /etc/hysteria
            printf "${GREEN}Configuration files removed.${NC}\n"
        fi
        printf "${GREEN}Hysteria 2 uninstalled successfully.${NC}\n"
    else
        printf "${GREEN}Uninstallation cancelled.${NC}\n"
    fi
    printf "Press Enter to return to menu..."
    read dummy
}

generate_random_password() {
    LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

configure_hysteria() {
    mkdir -p /etc/hysteria
    CONFIG_FILE="/etc/hysteria/config.yaml"
    
    printf "${CYAN}--- Hysteria 2 Configuration Wizard ---${NC}\n"
    
    # 1. Port
    printf "Enter listen port (Default: 443): "
    read port
    port=${port:-443}

    # 2. TLS config
    printf "\n${CYAN}--- TLS Configuration ---${NC}\n"
    printf "Choose certificate option:\n"
    printf "1) Auto-generate a self-signed certificate (e.g., for kimyfly.com)\n"
    printf "2) Provide existing certificate files\n"
    printf "Choice (Default: 1): "
    read cert_choice
    cert_choice=${cert_choice:-1}
    
    if [ "$cert_choice" = "1" ]; then
        printf "Enter a domain for the self-signed certificate (e.g., kimyfly.com): "
        read self_domain
        self_domain=${self_domain:-kimyfly.com}
        printf "${YELLOW}Generating self-signed certificate for $self_domain...${NC}\n"
        
        cert_path="/etc/hysteria/server.crt"
        key_path="/etc/hysteria/server.key"
        
        # Create private key
        openssl genrsa -out "$key_path" 2048 2>/dev/null
        
        # Create self-signed certificate with subjectAltName
        openssl req -new -x509 -days 3650 -key "$key_path" -out "$cert_path" \
            -subj "/CN=$self_domain" \
            -addext "subjectAltName=DNS:$self_domain,DNS:*.$self_domain" 2>/dev/null
            
        printf "${GREEN}Certificate generated at $cert_path${NC}\n"
        tls_config="tls:
  cert: $cert_path
  key: $key_path"
    else
        printf "Enter certificate file path (/path/to/cert.crt): "
        read cert_path
        printf "Enter key file path (/path/to/key.key): "
        read key_path
        printf "Enter SNI (Server Name Indication, optional): "
        read sni
        
        if [ -n "$sni" ]; then
            tls_config="tls:
  cert: $cert_path
  key: $key_path
  sni: $sni"
        else
            tls_config="tls:
  cert: $cert_path
  key: $key_path"
        fi
    fi

    # 3. Auth
    printf "\n${CYAN}--- Auth Configuration ---${NC}\n"
    printf "Enter an auth password (leave blank to generate randomly): "
    read password
    if [ -z "$password" ]; then
        password=$(generate_random_password)
        printf "${GREEN}Generated password: ${password}${NC}\n"
    fi
    auth_config="auth:
  type: password
  password: $password"

    # 4. Masquerade
    printf "\n${CYAN}--- Masquerade Configuration ---${NC}\n"
    printf "Enter proxy masquerade URL (Default: https://bing.com): "
    read masq_url
    masq_url=${masq_url:-https://bing.com}

    # Generate config
    printf "${YELLOW}Generating configuration...${NC}\n"
    cat > "$CONFIG_FILE" <<EOF
listen: :$port

$tls_config

$auth_config

masquerade:
  type: proxy
  proxy:
    url: $masq_url
    rewriteHost: true
EOF

    printf "${GREEN}Configuration saved to $CONFIG_FILE${NC}\n"
    
    # Generate client link
    printf "${YELLOW}Fetching public IP to generate client link...${NC}\n"
    public_ip=$(curl -sS ipv4.icanhazip.com || curl -sS ifconfig.me)
    # determine SNI for link
    if [ "$cert_choice" = "1" ]; then
        link_sni=$self_domain
        insecure=1
    else
        link_sni=${sni:-$public_ip}
        insecure=0
    fi
    current_date=$(date +%Y%m%d)
    
    client_link="hysteria2://${password}@${public_ip}:${port}/?SNI=${link_sni}&insecure=${insecure}#Hysteria-${current_date}"
    printf "\n${CYAN}=================================${NC}\n"
    printf "${GREEN}Client Connection Link:${NC}\n"
    printf "%s\n" "${client_link}"
    printf "${CYAN}=================================${NC}\n\n"

    printf "Do you want to restart hysteria-server now to apply changes? [Y/n]: "
    read restart_choice
    restart_choice=${restart_choice:-Y}
    if [ "$restart_choice" = "y" ] || [ "$restart_choice" = "Y" ]; then
        systemctl restart hysteria-server
        printf "${GREEN}Service restarted.${NC}\n"
    fi
    printf "Press Enter to return to menu..."
    read dummy
}

while true; do
    show_menu
done
