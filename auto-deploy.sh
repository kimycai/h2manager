#!/usr/bin/env bash

# Hysteria 2 一键部署脚本
# 自动完成安装、配置、启动、显示客户端链接和配置防火墙

set -e

# 颜色定义
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

# 打印信息函数
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "需要 root 权限执行此脚本"
        echo "请使用: sudo bash auto-deploy.sh"
        exit 1
    fi
}

# 安装 Hysteria 2
install_hysteria() {
    info "开始安装 Hysteria 2..."
    
    # 执行官方安装脚本
    if curl -fsSL https://get.hy2.sh/ | bash; then
        if [ -f "/usr/local/bin/hysteria" ]; then
            success "Hysteria 2 安装完成"
        else
            error "Hysteria 二进制文件未找到"
            return 1
        fi
    else
        error "Hysteria 2 安装失败"
        return 1
    fi
}

# 创建 systemd 服务文件
create_service() {
    info "创建 systemd 服务文件..."
    
    local service_file="/etc/systemd/system/hysteria-server.service"
    
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
    
    chmod 644 "$service_file"
    systemctl daemon-reload
    success "systemd 服务文件创建完成"
}

# 自动配置 Hysteria 2
auto_configure() {
    info "开始自动配置 Hysteria 2..."
    
    # 创建配置目录
    mkdir -p /etc/hysteria
    
    # 获取公网 IP
    info "获取公网 IP 地址..."
    local public_ip=$(curl -sS ipv4.icanhazip.com || curl -sS ifconfig.me)
    
    # 生成随机密码（20位）
    local password=$(openssl rand -base64 15 | tr -d '=+/' | head -c 20)
    
    # 使用自签名证书
    info "生成自签名证书..."
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=$public_ip" -days 3650
    
    # 生成配置文件
    info "生成配置文件..."
    cat > /etc/hysteria/config.yaml << EOF
listen: :443

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
  sniGuard: dns-san

auth:
  type: password
  password: $password

# masquerade:
#   type: proxy
#   proxy:
#     url: "https://bing.com"
#     rewriteHost: true
EOF
    
    success "Hysteria 2 配置完成"
    echo "服务器地址: $public_ip:443"
    echo "连接密码: $password"
}

# 启动 Hysteria 服务
start_service() {
    info "启动 Hysteria 服务..."
    
    # 启用开机自启动
    systemctl enable hysteria-server
    
    # 启动服务
    if systemctl start hysteria-server; then
        success "Hysteria 服务启动成功"
        
        # 检查服务状态
        if systemctl is-active --quiet hysteria-server; then
            success "Hysteria 服务运行正常"
        else
            warning "Hysteria 服务状态异常"
            systemctl status hysteria-server --no-pager
        fi
    else
        error "Hysteria 服务启动失败"
        return 1
    fi
}

# 生成客户端链接
generate_client_link() {
    info "生成客户端连接链接..."
    
    local config_file="/etc/hysteria/config.yaml"
    
    if [ ! -f "$config_file" ]; then
        error "配置文件未找到"
        return 1
    fi
    
    # 从配置文件中提取信息
    local listen_port=$(grep "listen:" "$config_file" | awk '{print $2}' | cut -d: -f2)
    local password=$(grep "password:" "$config_file" | awk '{print $2}')
    
    # 获取公网 IP
    local public_ip=$(curl -sS ipv4.icanhazip.com || curl -sS ifconfig.me)
    
    # 生成客户端链接
    local current_date=$(date +%Y%m%d)
    local client_link="hysteria2://${password}@${public_ip}:${listen_port}/?SNI=${public_ip}&insecure=1#Hysteria-${current_date}"
    
    echo ""
    echo -e "${CYAN}=================================${NC}"
    echo -e "${GREEN}客户端连接链接:${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo ""
    echo -e "${YELLOW}$client_link${NC}"
    echo ""
    echo -e "${CYAN}=================================${NC}"
    echo ""
    
    # 显示配置信息
    echo -e "${GREEN}配置信息摘要:${NC}"
    echo "服务器地址: $public_ip:$listen_port"
    echo "连接密码: $password"
    echo "SNI: $public_ip"
    echo "安全模式: 1 (自签名证书)"
    echo ""
}

# 配置防火墙
configure_firewall() {
    # 检查 iptables 是否可用
    if ! command -v iptables &> /dev/null; then
        warning "iptables 未安装，跳过防火墙配置"
        return 0
    fi
    
    # 显示当前防火墙状态
    echo ""
    echo -e "${CYAN}当前防火墙状态:${NC}"
    echo "INPUT 链策略: $(iptables -L INPUT -n --line-numbers | head -1 | awk '{print $4}')"
    echo "FORWARD 链策略: $(iptables -L FORWARD -n --line-numbers | head -1 | awk '{print $4}')"
    echo "OUTPUT 链策略: $(iptables -L OUTPUT -n --line-numbers | head -1 | awk '{print $4}')"
    echo ""
    
    # 询问是否配置防火墙
    echo -e "${YELLOW}是否配置防火墙? [Y/n]: ${NC}"
    echo "这将设置默认策略为 ACCEPT 并清空所有规则"
    read firewall_confirm
    firewall_confirm=${firewall_confirm:-Y}
    
    if [ "$firewall_confirm" != "y" ] && [ "$firewall_confirm" != "Y" ]; then
        warning "跳过防火墙配置"
        return 0
    fi
    
    info "配置防火墙..."
    
    # 执行防火墙配置
    info "设置防火墙规则..."
    
    if iptables -P INPUT ACCEPT && \
       iptables -P FORWARD ACCEPT && \
       iptables -P OUTPUT ACCEPT && \
       iptables -F; then
        success "防火墙配置完成"
        
        # 显示配置后的状态
        echo "配置后的防火墙状态:"
        echo "INPUT 链策略: $(iptables -L INPUT -n --line-numbers | head -1 | awk '{print $4}')"
        echo "FORWARD 链策略: $(iptables -L FORWARD -n --line-numbers | head -1 | awk '{print $4}')"
        echo "OUTPUT 链策略: $(iptables -L OUTPUT -n --line-numbers | head -1 | awk '{print $4}')"
    else
        error "防火墙配置失败"
        return 1
    fi
}

# 显示部署摘要
show_summary() {
    echo ""
    echo -e "${CYAN}=================================${NC}"
    echo -e "${GREEN}       部署完成摘要           ${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo ""
    echo -e "${GREEN}✓ Hysteria 2 安装完成${NC}"
    echo -e "${GREEN}✓ 配置文件生成完成${NC}"
    echo -e "${GREEN}✓ 自签名证书创建完成${NC}"
    echo -e "${GREEN}✓ systemd 服务配置完成${NC}"
    echo -e "${GREEN}✓ 服务启动并启用开机自启动${NC}"
    echo -e "${GREEN}✓ 防火墙配置完成${NC}"
    echo ""
    echo -e "${YELLOW}重要提示:${NC}"
    echo "1. 请妥善保管客户端连接链接"
    echo "2. 防火墙已设置为允许所有连接"
    echo "3. 服务已配置开机自启动"
    echo "4. 使用自签名证书，客户端需设置 insecure=1"
    echo ""
}

# 确认部署
confirm_deployment() {
    echo -e "${CYAN}=================================${NC}"
    echo -e "${GREEN}   Hysteria 2 一键部署脚本     ${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo ""
    echo -e "${YELLOW}即将执行以下操作:${NC}"
    echo "1. 安装 Hysteria 2"
    echo "2. 创建 systemd 服务"
    echo "3. 自动配置（生成密码、证书、配置文件）"
    echo "4. 启动服务并设置开机自启动"
    echo "5. 生成客户端连接链接"
    echo "6. 配置防火墙（允许所有连接）"
    echo ""
    echo -e "${RED}警告: 这将清空现有防火墙规则${NC}"
    echo -e "${YELLOW}是否继续部署? [y/N]: ${NC}"
    read confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "部署已取消"
        exit 0
    fi
    echo ""
}

# 主函数
main() {
    # 检查 root 权限
    check_root
    
    # 确认部署
    confirm_deployment
    
    # 执行部署步骤
    install_hysteria || exit 1
    create_service || exit 1
    auto_configure || exit 1
    start_service || exit 1
    generate_client_link || exit 1
    configure_firewall || exit 1
    
    # 显示部署摘要
    show_summary
    
    success "Hysteria 2 一键部署完成！"
    echo ""
    echo "脚本执行完毕，即将退出..."
    sleep 2
}

# 执行主函数
main "$@"
