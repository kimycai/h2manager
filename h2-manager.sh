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
    printf "${CYAN}       Hysteria 2 管理脚本        ${NC}\n"
    printf "${CYAN}=================================${NC}\n"
    printf "1. 安装 Hysteria 2\n"
    printf "2. 卸载 Hysteria 2\n"
    printf "3. 配置 Hysteria 2 (向导)\n"
    printf "4. 启动服务\n"
    printf "5. 停止服务\n"
    printf "6. 重启服务\n"
    printf "7. 查看状态\n"
    printf "8. 查看证书\n"
    printf "9. 生成客户端链接\n"
    printf "10. 配置防火墙\n"
    printf "0. 退出\n"
    printf "${CYAN}=================================${NC}\n"
    printf "请输入选择: "
    read choice
    case $choice in
        1) install_hysteria ;;
        2) uninstall_hysteria ;;
        3) configure_hysteria ;;
        4) systemctl start hysteria-server && printf "${GREEN}服务已启动.${NC}\n" ; printf "按回车键返回..." ; read dummy ;;
        5) systemctl stop hysteria-server && printf "${YELLOW}服务已停止.${NC}\n" ; printf "按回车键返回..." ; read dummy ;;
        6) systemctl restart hysteria-server && printf "${GREEN}服务已重启.${NC}\n" ; printf "按回车键返回..." ; read dummy ;;
        7) systemctl status hysteria-server ;;
        8) view_certificate ;;
        9) generate_client_link ;;
        10) configure_firewall ;;
        0) exit 0 ;;
        *) printf "${RED}无效选项${NC}\n"; sleep 1 ;;
    esac
}

# 创建 systemd 服务文件
create_systemd_service() {
    local service_file="/etc/systemd/system/hysteria-server.service"
    
    printf "${CYAN}Creating systemd service file...${NC}\n"
    
    # 创建正确的服务文件
    cat > "$service_file" << 'EOF'
[Unit]
Description=Hysteria Server Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server --config /etc/hysteria/config.yaml
Restart=always
RestartSec=3
User=root
WorkingDirectory=/tmp

[Install]
WantedBy=multi-user.target
EOF
    
    # 设置正确的权限
    chmod 644 "$service_file"
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    printf "${GREEN}Systemd service file created: $service_file${NC}\n"
}

# 安装 Hysteria 2 服务器
install_hysteria() {
    printf "${GREEN}开始官方 Hysteria 2 安装...${NC}\n"
    
    # 执行官方安装脚本
    curl -fsSL https://get.hy2.sh/ | bash
    
    # 检查安装是否成功
    if [ $? -eq 0 ] && [ -f "/usr/local/bin/hysteria" ]; then
        printf "${GREEN}安装完成.${NC}\n"
        
        # 创建正确的 systemd 服务文件
        create_systemd_service
        
        # 启用并启动服务
        systemctl enable hysteria-server
        systemctl start hysteria-server
        
        printf "${GREEN}Hysteria 2 服务已启用并启动.${NC}\n"
    else
        printf "${RED}安装失败或未找到 hysteria 二进制文件.${NC}\n"
        printf "按回车键返回菜单..."
        read dummy
        return 1
    fi
    
    printf "按回车键返回菜单..."
    read dummy
}

uninstall_hysteria() {
    printf "${YELLOW}警告: 这将从系统中移除 Hysteria 2.${NC}\n"
    printf "确定要继续吗? [y/N]: "
    read confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        systemctl stop hysteria-server
        systemctl disable hysteria-server
        rm -f /etc/systemd/system/hysteria-server.service
        rm -f /etc/systemd/system/hysteria-server@.service
        systemctl daemon-reload
        rm -f /usr/local/bin/hysteria
        printf "是否要移除配置文件 (/etc/hysteria)? [y/N]: "
        read rm_config
        if [ "$rm_config" = "y" ] || [ "$rm_config" = "Y" ]; then
            rm -rf /etc/hysteria
            printf "${GREEN}配置文件已移除.${NC}\n"
        fi
        printf "${GREEN}Hysteria 2 卸载成功.${NC}\n"
    else
        printf "${GREEN}卸载已取消.${NC}\n"
    fi
    printf "按回车键返回菜单..."
    read dummy
}

generate_random_password() {
    LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

configure_hysteria() {
    mkdir -p /etc/hysteria
    CONFIG_FILE="/etc/hysteria/config.yaml"
    
    printf "${CYAN}--- Hysteria 2 配置向导 ---${NC}\n"
    
    # 1. 端口
    printf "请输入监听端口 (默认: 443): "
    read port
    port=${port:-443}

    # 2. TLS 配置
    printf "\n${CYAN}--- TLS 配置 ---${NC}\n"
    printf "选择证书选项:\n"
    printf "1) 自动生成自签证书 (例如: kimyfly.com)\n"
    printf "2) 提供现有证书文件\n"
    printf "选择 (默认: 1): "
    read cert_choice
    cert_choice=${cert_choice:-1}
    
    if [ "$cert_choice" = "1" ]; then
        printf "请输入自签证书的域名 (例如: kimyfly.com): "
        read self_domain
        self_domain=${self_domain:-kimyfly.com}
        printf "${YELLOW}正在为 $self_domain 生成自签证书...${NC}\n"
        
        cert_path="/etc/hysteria/server.crt"
        key_path="/etc/hysteria/server.key"
        
        # 创建私钥
        openssl genrsa -out "$key_path" 2048 2>/dev/null
        
        # 创建带 subjectAltName 的自签证书
        openssl req -new -x509 -days 3650 -key "$key_path" -out "$cert_path" \
            -subj "/CN=$self_domain" \
            -addext "subjectAltName=DNS:$self_domain,DNS:*.$self_domain" 2>/dev/null
            
        printf "${GREEN}证书已生成: $cert_path${NC}\n"
        tls_config="tls:
  cert: \"$cert_path\"
  key: \"$key_path\"
  sniGuard: dns-san"
    else
        printf "请输入证书文件路径 (/path/to/cert.crt): "
        read cert_path
        printf "请输入私钥文件路径 (/path/to/key.key): "
        read key_path
        printf "请输入 SNI (服务器名称指示，可选): "
        read sni
        
        if [ -n "$sni" ]; then
            tls_config="tls:
  cert: \"$cert_path\"
  key: \"$key_path\"
  sni: $sni
  sniGuard: dns-san"
        else
            tls_config="tls:
  cert: \"$cert_path\"
  key: \"$key_path\"
  sniGuard: dns-san"
        fi
    fi

    # 3. 认证配置
    printf "\n${CYAN}--- 认证配置 ---${NC}\n"
    printf "请输入认证密码 (留空自动生成随机密码): "
    read password
    if [ -z "$password" ]; then
        password=$(generate_random_password)
        printf "${GREEN}生成的密码: ${password}${NC}\n"
    fi
    auth_config="auth:
  type: password
  password: \"$password\""

    # 4. Masquerade (注释掉)
    # printf "\n${CYAN}--- 伪装配置 ---${NC}\n"
    # printf "请输入代理伪装 URL (默认: https://bing.com): "
    # read masq_url
    # masq_url=${masq_url:-https://bing.com}

    # 生成配置
    printf "${YELLOW}正在生成配置...${NC}\n"
    cat > "$CONFIG_FILE" <<EOF
listen: :$port

$tls_config

$auth_config

# masquerade:
#   type: proxy
#   proxy:
#     url: \"https://bing.com\"
#     rewriteHost: true
EOF

    printf "${GREEN}配置已保存到 $CONFIG_FILE${NC}\n"
    
    # 生成客户端链接
    printf "${YELLOW}正在获取公网 IP 以生成客户端链接...${NC}\n"
    public_ip=$(curl -sS ipv4.icanhazip.com || curl -sS ifconfig.me)
    # 确定链接的 SNI
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
    printf "${GREEN}客户端连接链接:${NC}\n"
    printf "%s\n" "${client_link}"
    printf "${CYAN}=================================${NC}\n\n"

    # 确保 systemd 服务文件存在且正确
    printf "${YELLOW}正在检查 systemd 服务文件...${NC}\n"
    if [ ! -f "/etc/systemd/system/hysteria-server.service" ]; then
        printf "${YELLOW}正在创建 systemd 服务文件...${NC}\n"
        create_systemd_service
    else
        # 检查现有服务文件是否正确
        if ! grep -q "WorkingDirectory=/tmp" "/etc/systemd/system/hysteria-server.service" || \
           ! grep -q "User=root" "/etc/systemd/system/hysteria-server.service"; then
            printf "${YELLOW}正在修复 systemd 服务文件...${NC}\n"
            create_systemd_service
        else
            printf "${GREEN}Systemd 服务文件正确.${NC}\n"
        fi
    fi

    printf "是否现在重启 hysteria-server 以应用更改? [Y/n]: "
    read restart_choice
    restart_choice=${restart_choice:-Y}
    if [ "$restart_choice" = "y" ] || [ "$restart_choice" = "Y" ]; then
        systemctl restart hysteria-server
        printf "${GREEN}服务已重启.${NC}\n"
    fi
    printf "按回车键返回菜单..."
    read dummy
}

# 查看证书信息
view_certificate() {
    local cert_file="/etc/hysteria/server.crt"
    
    # 检查证书文件是否存在
    if [ ! -f "$cert_file" ]; then
        printf "${RED}证书文件未找到: $cert_file${NC}\n"
        printf "${YELLOW}请先运行配置向导.${NC}\n"
        printf "按回车键返回菜单..."
        read dummy
        return 1
    fi
    
    # 直接显示证书 PEM 内容
    cat "$cert_file"
    printf "\n"
    printf "按回车键返回菜单..."
    read dummy
}

# 生成客户端链接
generate_client_link() {
    local config_file="/etc/hysteria/config.yaml"
    local cert_file="/etc/hysteria/server.crt"
    
    # 检查配置文件是否存在
    if [ ! -f "$config_file" ]; then
        printf "${RED}配置文件未找到: $config_file${NC}\n"
        printf "${YELLOW}请先运行配置向导.${NC}\n"
        printf "按回车键返回菜单..."
        read dummy
        return 1
    fi
    
    # 检查证书文件是否存在
    if [ ! -f "$cert_file" ]; then
        printf "${RED}证书文件未找到: $cert_file${NC}\n"
        printf "${YELLOW}请先运行配置向导.${NC}\n"
        printf "按回车键返回菜单..."
        read dummy
        return 1
    fi
    
    # 从配置文件中提取信息
    local listen_port=$(grep "listen:" "$config_file" | awk '{print $2}' | cut -d: -f2)
    local password=$(grep "password:" "$config_file" | awk '{print $2}')
    
    # 获取公网 IP
    printf "${YELLOW}正在获取公网 IP...${NC}\n"
    local public_ip=$(curl -sS ipv4.icanhazip.com || curl -sS ifconfig.me)
    
    # 确定 SNI 和 insecure 参数
    local sni=""
    local insecure=0
    
    # 检查是否使用自签名证书
    if grep -q "self-signed" "$config_file" || ! grep -q "sni:" "$config_file"; then
        sni=$public_ip
        insecure=1
    else
        sni=$(grep "sni:" "$config_file" | awk '{print $2}')
        insecure=0
    fi
    
    # 生成当前日期
    local current_date=$(date +%Y%m%d)
    
    # 生成客户端链接
    local client_link="hysteria2://${password}@${public_ip}:${listen_port}/?SNI=${sni}&insecure=${insecure}#Hysteria-${current_date}"
    
    # 显示链接
    printf "\n${CYAN}=================================${NC}\n"
    printf "${GREEN}客户端连接链接:${NC}\n"
    printf "${CYAN}=================================${NC}\n"
    printf "\n"
    printf "${YELLOW}%s${NC}\n" "${client_link}"
    printf "\n"
    printf "${CYAN}=================================${NC}\n"
    printf "\n"
    
    # 显示配置信息摘要
    printf "${GREEN}配置信息摘要:${NC}\n"
    printf "服务器地址: ${public_ip}:${listen_port}\n"
    printf "连接密码: ${password}\n"
    printf "SNI: ${sni}\n"
    printf "安全模式: ${insecure}\n"
    printf "\n"
    
    # 使用说明
    printf "${CYAN}使用说明:${NC}\n"
    printf "${GREEN}✓ 复制上方链接到 Hysteria 2 客户端${NC}\n"
    printf "${GREEN}✓ 或手动输入配置信息${NC}\n"
    printf "${YELLOW}⚠️  请妥善保管链接，避免泄露${NC}\n"
    printf "\n"
    
    printf "按回车键返回菜单..."
    read dummy
}

# 配置防火墙
configure_firewall() {
    printf "${CYAN}=================================${NC}\n"
    printf "${CYAN}       防火墙配置工具           ${NC}\n"
    printf "${CYAN}=================================${NC}\n"
    printf "\n"
    
    # 检查是否具有 root 权限
    if [ "$EUID" -ne 0 ]; then
        printf "${YELLOW}警告: 需要 root 权限执行防火墙配置${NC}\n"
        printf "请使用 sudo 运行此脚本或切换到 root 用户\n"
        printf "按回车键返回菜单..."
        read dummy
        return 1
    fi
    
    # 检查 iptables 是否可用
    if ! command -v iptables &> /dev/null; then
        printf "${RED}错误: iptables 命令未找到${NC}\n"
        printf "请确保系统已安装 iptables\n"
        printf "按回车键返回菜单..."
        read dummy
        return 1
    fi
    
    # 显示当前防火墙状态
    printf "${GREEN}当前防火墙状态:${NC}\n"
    printf "\n"
    printf "INPUT 链策略: $(iptables -L INPUT -n --line-numbers | head -1 | awk '{print $4}')\n"
    printf "FORWARD 链策略: $(iptables -L FORWARD -n --line-numbers | head -1 | awk '{print $4}')\n"
    printf "OUTPUT 链策略: $(iptables -L OUTPUT -n --line-numbers | head -1 | awk '{print $4}')\n"
    printf "\n"
    
    # 确认操作
    printf "${YELLOW}即将执行以下防火墙配置:${NC}\n"
    printf "sudo iptables -P INPUT ACCEPT\n"
    printf "sudo iptables -P FORWARD ACCEPT\n"
    printf "sudo iptables -P OUTPUT ACCEPT\n"
    printf "sudo iptables -F\n"
    printf "\n"
    printf "${RED}警告: 这将清空所有防火墙规则并设置默认允许策略${NC}\n"
    printf "是否继续? [y/N]: "
    read confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        printf "${YELLOW}操作已取消${NC}\n"
        printf "按回车键返回菜单..."
        read dummy
        return 0
    fi
    
    # 执行防火墙配置
    printf "\n${YELLOW}正在配置防火墙...${NC}\n"
    printf "\n"
    
    # 设置默认策略为 ACCEPT
    printf "设置 INPUT 链策略为 ACCEPT...\n"
    if iptables -P INPUT ACCEPT; then
        printf "${GREEN}✓ 成功${NC}\n"
    else
        printf "${RED}✗ 失败${NC}\n"
    fi
    
    printf "设置 FORWARD 链策略为 ACCEPT...\n"
    if iptables -P FORWARD ACCEPT; then
        printf "${GREEN}✓ 成功${NC}\n"
    else
        printf "${RED}✗ 失败${NC}\n"
    fi
    
    printf "设置 OUTPUT 链策略为 ACCEPT...\n"
    if iptables -P OUTPUT ACCEPT; then
        printf "${GREEN}✓ 成功${NC}\n"
    else
        printf "${RED}✗ 失败${NC}\n"
    fi
    
    # 清空所有规则
    printf "清空所有防火墙规则...\n"
    if iptables -F; then
        printf "${GREEN}✓ 成功${NC}\n"
    else
        printf "${RED}✗ 失败${NC}\n"
    fi
    
    printf "\n"
    
    # 显示配置后的状态
    printf "${GREEN}配置完成后的防火墙状态:${NC}\n"
    printf "\n"
    printf "INPUT 链策略: $(iptables -L INPUT -n --line-numbers | head -1 | awk '{print $4}')\n"
    printf "FORWARD 链策略: $(iptables -L FORWARD -n --line-numbers | head -1 | awk '{print $4}')\n"
    printf "OUTPUT 链策略: $(iptables -L OUTPUT -n --line-numbers | head -1 | awk '{print $4}')\n"
    printf "\n"
    
    # 显示规则数量
    printf "当前规则数量:\n"
    printf "INPUT 链: $(iptables -L INPUT -n --line-numbers | wc -l) 条规则\n"
    printf "FORWARD 链: $(iptables -L FORWARD -n --line-numbers | wc -l) 条规则\n"
    printf "OUTPUT 链: $(iptables -L OUTPUT -n --line-numbers | wc -l) 条规则\n"
    printf "\n"
    
    # 使用说明
    printf "${CYAN}使用说明:${NC}\n"
    printf "${GREEN}✓ 所有防火墙规则已清空${NC}\n"
    printf "${GREEN}✓ 默认策略已设置为 ACCEPT${NC}\n"
    printf "${YELLOW}⚠️  这可能会降低系统安全性${NC}\n"
    printf "${YELLOW}⚠️  建议在生产环境中配置更严格的防火墙规则${NC}\n"
    printf "\n"
    
    printf "${GREEN}防火墙配置完成${NC}\n"
    printf "按回车键返回菜单..."
    read dummy
}

while true; do
    show_menu
done
