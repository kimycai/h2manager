#!/bin/bash
# hysteria-manager.sh
# description: official Hysteria 2 installation, uninstallation, and configuration wizard

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

function show_menu() {
    clear
    echo -e "${CYAN}=================================${NC}"
    echo -e "${CYAN}   Hysteria 2 Manager Script     ${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo -e "1. Install Hysteria 2"
    echo -e "2. Uninstall Hysteria 2"
    echo -e "3. Configure Hysteria 2 (Wizard)"
    echo -e "4. Start Service"
    echo -e "5. Stop Service"
    echo -e "6. Restart Service"
    echo -e "7. View Status"
    echo -e "0. Exit"
    echo -e "${CYAN}=================================${NC}"
    read -p "Enter your choice: " choice
    case $choice in
        1) install_hysteria ;;
        2) uninstall_hysteria ;;
        3) configure_hysteria ;;
        4) systemctl start hysteria-server && echo -e "${GREEN}Service started.${NC}" ; read -p "Press Enter to return..." ;;
        5) systemctl stop hysteria-server && echo -e "${YELLOW}Service stopped.${NC}" ; read -p "Press Enter to return..." ;;
        6) systemctl restart hysteria-server && echo -e "${GREEN}Service restarted.${NC}" ; read -p "Press Enter to return..." ;;
        7) systemctl status hysteria-server ; read -p "Press Enter to return..." ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
    esac
}

function install_hysteria() {
    echo -e "${GREEN}Starting official Hysteria 2 installation...${NC}"
    bash <(curl -fsSL https://get.hy2.sh/)
    echo -e "${GREEN}Installation completed.${NC}"
    read -p "Press Enter to return to menu..."
}

function uninstall_hysteria() {
    echo -e "${YELLOW}WARNING: This will remove Hysteria 2 from your system.${NC}"
    read -p "Are you sure? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        systemctl stop hysteria-server
        systemctl disable hysteria-server
        rm -f /etc/systemd/system/hysteria-server.service
        rm -f /etc/systemd/system/hysteria-server@.service
        systemctl daemon-reload
        rm -f /usr/local/bin/hysteria
        read -p "Do you want to remove configuration files (/etc/hysteria)? [y/N]: " rm_config
        if [[ "$rm_config" =~ ^[Yy]$ ]]; then
            rm -rf /etc/hysteria
            echo -e "${GREEN}Configuration files removed.${NC}"
        fi
        echo -e "${GREEN}Hysteria 2 uninstalled successfully.${NC}"
    else
        echo -e "${GREEN}Uninstallation cancelled.${NC}"
    fi
    read -p "Press Enter to return to menu..."
}

function generate_random_password() {
    LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

function configure_hysteria() {
    mkdir -p /etc/hysteria
    CONFIG_FILE="/etc/hysteria/config.yaml"
    
    echo -e "${CYAN}--- Hysteria 2 Configuration Wizard ---${NC}"
    
    # 1. Port
    read -p "Enter listen port (Default: 443): " port
    port=${port:-443}

    # 2. TLS config
    echo -e "\n${CYAN}--- TLS Configuration ---${NC}"
    echo -e "Choose certificate option:"
    echo -e "1) Auto-generate a self-signed certificate (e.g., for kimyfly.com)"
    echo -e "2) Provide existing certificate files"
    read -p "Choice (Default: 1): " cert_choice
    cert_choice=${cert_choice:-1}
    
    if [ "$cert_choice" == "1" ]; then
        read -p "Enter a domain for the self-signed certificate (e.g., kimyfly.com): " self_domain
        self_domain=${self_domain:-kimyfly.com}
        echo -e "${YELLOW}Generating self-signed certificate for $self_domain...${NC}"
        
        cert_path="/etc/hysteria/server.crt"
        key_path="/etc/hysteria/server.key"
        
        # Create private key
        openssl genrsa -out "$key_path" 2048 2>/dev/null
        
        # Create self-signed certificate with subjectAltName
        openssl req -new -x509 -days 3650 -key "$key_path" -out "$cert_path" \
            -subj "/CN=$self_domain" \
            -addext "subjectAltName=DNS:$self_domain,DNS:*.$self_domain" 2>/dev/null
            
        echo -e "${GREEN}Certificate generated at $cert_path${NC}"
        tls_config="tls:
  cert: $cert_path
  key: $key_path"
    else
        read -p "Enter certificate file path (/path/to/cert.crt): " cert_path
        read -p "Enter key file path (/path/to/key.key): " key_path
        read -p "Enter SNI (Server Name Indication, optional): " sni
        
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
    echo -e "\n${CYAN}--- Auth Configuration ---${NC}"
    read -p "Enter an auth password (leave blank to generate randomly): " password
    if [ -z "$password" ]; then
        password=$(generate_random_password)
        echo -e "${GREEN}Generated password: ${password}${NC}"
    fi
    auth_config="auth:
  type: password
  password: $password"

    # 4. Masquerade
    echo -e "\n${CYAN}--- Masquerade Configuration ---${NC}"
    read -p "Enter proxy masquerade URL (Default: https://bing.com): " masq_url
    masq_url=${masq_url:-https://bing.com}

    # Generate config
    echo -e "${YELLOW}Generating configuration...${NC}"
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

    echo -e "${GREEN}Configuration saved to $CONFIG_FILE${NC}"
    
    # Generate client link
    echo -e "${YELLOW}Fetching public IP to generate client link...${NC}"
    public_ip=$(curl -sS ipv4.icanhazip.com || curl -sS ifconfig.me)
    # determine SNI for link
    if [ "$cert_choice" == "1" ]; then
        link_sni=$self_domain
        insecure=1
    else
        link_sni=${sni:-$public_ip}
        insecure=0
    fi
    current_date=$(date +%Y%m%d)
    
    client_link="hysteria2://${password}@${public_ip}:${port}/?SNI=${link_sni}&insecure=${insecure}#Hysteria-${current_date}"
    echo -e "\n${CYAN}=================================${NC}"
    echo -e "${GREEN}Client Connection Link:${NC}"
    echo -e "${client_link}"
    echo -e "${CYAN}=================================${NC}\n"

    read -p "Do you want to restart hysteria-server now to apply changes? [Y/n]: " restart_choice
    restart_choice=${restart_choice:-Y}
    if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
        systemctl restart hysteria-server
        echo -e "${GREEN}Service restarted.${NC}"
    fi
    read -p "Press Enter to return to menu..."
}

while true; do
    show_menu
done
