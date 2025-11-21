#!/usr/bin/env bash
#
# MTG Proxy 一键安装脚本
# 项目地址: https://github.com/interesmazing/mtg-proxy-installer
# MTG 项目: https://github.com/9seconds/mtg
# 适用系统: Ubuntu 24.04 LTS x64
#

set -e

# ============================================
# 配置常量
# ============================================

readonly BINEXEC="/usr/local/bin/mtg"
readonly CONFIG_FILE="/etc/mtg.toml"
readonly SERVICE_FILE="/etc/systemd/system/mtg.service"
readonly MTG_REPO="9seconds/mtg"

# 默认配置
readonly DEFAULT_PORT="8440"
readonly DEFAULT_DOMAIN="azure.microsoft.com"
readonly DEFAULT_TAG=""

# 性能配置
readonly BIND_TO="0.0.0.0"
readonly CONCURRENCY="2048"
readonly TCP_BUFFER="256kb"
readonly DOH_IP="1.1.1.1"
readonly BLOCKLIST_URL="https://raw.githubusercontent.com/stamparm/ipsum/master/levels/3.txt"
readonly BLOCKLIST_UPDATE="12h"
readonly TIMEOUT_TCP="3s"
readonly TIMEOUT_HTTP="5s"
readonly TIMEOUT_IDLE="30s"

# ============================================
# 颜色输出函数
# ============================================

red() {
    echo -e "\033[31m$*\033[0m"
}

green() {
    echo -e "\033[32m$*\033[0m"
}

yellow() {
    echo -e "\033[33m$*\033[0m"
}

blue() {
    echo -e "\033[34m$*\033[0m"
}

cyan() {
    echo -e "\033[36m$*\033[0m"
}

# ============================================
# 错误处理
# ============================================

error_exit() {
    red "错误: $1"
    exit 1
}

# ============================================
# 系统检查
# ============================================

check_system() {
    # 检查是否为 root
    if [[ $EUID -ne 0 ]]; then
        error_exit "此脚本需要 root 权限运行，请使用 sudo"
    fi

    # 检查是否为 systemd 系统
    if [[ ! -d /run/systemd/system ]]; then
        error_exit "此脚本仅支持使用 systemd 的 Linux 发行版"
    fi

    # 检查必要命令
    local required_cmds="wget tar systemctl xxd"
    for cmd in $required_cmds; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            if [[ "$cmd" == "xxd" ]]; then
                yellow "正在安装 xxd..."
                if command -v apt-get >/dev/null 2>&1; then
                    apt-get update -qq && apt-get install -y xxd vim-common
                elif command -v yum >/dev/null 2>&1; then
                    yum install -y vim-common
                else
                    error_exit "无法安装 xxd，请手动安装后重试"
                fi
            else
                error_exit "缺少必要的命令: $cmd，请先安装"
            fi
        fi
    done

    green "✓ 系统检查通过"
}

# ============================================
# 获取系统架构
# ============================================

get_arch() {
    local arch
    arch=$(uname -m)
    
    case $arch in
        x86_64)
            echo "linux-amd64"
            ;;
        aarch64)
            echo "linux-arm64"
            ;;
        armv7l)
            echo "linux-arm"
            ;;
        i*86)
            echo "linux-386"
            ;;
        *)
            error_exit "不支持的系统架构: $arch"
            ;;
    esac
}

# ============================================
# 下载并安装 MTG
# ============================================

install_mtg() {
    yellow "\n正在下载 MTG..."
    
    local arch
    arch=$(get_arch)
    
    local download_url
    download_url=$(wget -qO- "https://api.github.com/repos/${MTG_REPO}/releases/latest" \
        | grep "browser_download_url.*${arch}" \
        | cut -d '"' -f 4)
    
    if [[ -z $download_url ]]; then
        error_exit "无法获取下载链接"
    fi
    
    local temp_file
    temp_file=$(mktemp --suffix=.tar.gz)
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # 清理函数
    cleanup() {
        rm -rf "$temp_file" "$temp_dir"
    }
    trap cleanup EXIT
    
    # 下载
    if ! wget -q --show-progress "$download_url" -O "$temp_file"; then
        error_exit "下载失败"
    fi
    
    # 解压
    yellow "正在解压..."
    if ! tar xf "$temp_file" --strip-components=1 -C "$temp_dir"; then
        error_exit "解压失败"
    fi
    
    # 停止现有服务
    if systemctl is-active --quiet mtg 2>/dev/null; then
        yellow "停止现有服务..."
        systemctl stop mtg
    fi
    
    # 安装
    yellow "正在安装..."
    install -m 755 "$temp_dir/mtg" "$BINEXEC"
    
    green "✓ MTG 安装完成"
    
    # 显示版本
    local version
    version=$("$BINEXEC" --version 2>&1 | head -n1)
    cyan "  版本: $version"
}

# ============================================
# 生成随机密钥
# ============================================

generate_random_secret() {
    head -c 16 /dev/urandom | xxd -ps
}

# ============================================
# 将域名转换为十六进制
# ============================================

domain_to_hex() {
    local domain=$1
    echo -n "$domain" | xxd -ps
}

# ============================================
# 构建完整的 MTG 密钥
# ============================================

build_mtg_secret() {
    local raw_secret=$1
    local domain=$2
    local tag=$3
    
    # 验证原始密钥格式（应该是32个十六进制字符）
    if [[ ! $raw_secret =~ ^[0-9a-fA-F]{32}$ ]]; then
        error_exit "密钥格式错误，应该是32位十六进制字符串"
    fi
    
    # 转换域名为十六进制
    local domain_hex
    domain_hex=$(domain_to_hex "$domain")
    
    # 构建完整密钥：ee + 原始密钥 + 域名十六进制
    local full_secret="ee${raw_secret}${domain_hex}"
    
    # 如果有 TAG，添加到末尾
    if [[ -n $tag ]]; then
        full_secret="${full_secret}${tag}"
    fi
    
    echo "$full_secret"
}

# ============================================
# 用户输入
# ============================================

get_user_input() {
    echo ""
    cyan "========================================"
    cyan "  请输入配置信息（直接回车使用默认值）"
    cyan "========================================"
    echo ""
    
    # 端口
    read -p "$(yellow '请输入服务端口 [默认: ')$(green "$DEFAULT_PORT")$(yellow ']: ')" input_port
    PORT=${input_port:-$DEFAULT_PORT}
    
    # 验证端口
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        error_exit "无效的端口号: $PORT"
    fi
    
    # 伪装域名
    read -p "$(yellow '请输入伪装域名 [默认: ')$(green "$DEFAULT_DOMAIN")$(yellow ']: ')" input_domain
    DOMAIN=${input_domain:-$DEFAULT_DOMAIN}
    
    # 密钥
    echo ""
    yellow "密钥设置："
    yellow "  1. 直接回车 - 自动生成随机密钥"
    yellow "  2. 输入32位十六进制字符串 - 使用自定义密钥"
    echo ""
    read -p "$(yellow '请输入密钥 [默认: ')$(green '自动生成')$(yellow ']: ')" input_secret
    
    if [[ -n $input_secret ]]; then
        # 验证用户输入的密钥格式
        if [[ ! $input_secret =~ ^[0-9a-fA-F]{32}$ ]]; then
            error_exit "密钥格式错误！应该是32位十六进制字符串（例如：fac4d5d2c59f89779bccffcd5d2cb151）"
        fi
        RAW_SECRET="$input_secret"
    else
        yellow "正在生成随机密钥..."
        RAW_SECRET=$(generate_random_secret)
        green "✓ 密钥已生成: $RAW_SECRET"
    fi
    
    # Telegram 频道
    echo ""
    read -p "$(yellow '请输入 Telegram 频道标签 [默认: ')$(green '无')$(yellow ']: ')" input_tag
    TAG=${input_tag:-$DEFAULT_TAG}
    
    # 移除 @ 符号
    TAG=${TAG#@}
    
    # 验证 TAG 格式（如果提供）
    if [[ -n $TAG ]] && [[ ! $TAG =~ ^[A-Za-z0-9]{32}$ ]]; then
        yellow "警告: TAG 格式可能不正确（应该是32位字母数字组合）"
        read -p "$(yellow '是否继续？[Y/n]: ')" confirm
        confirm=${confirm:-Y}
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            error_exit "已取消"
        fi
    fi
    
    # 构建完整的 MTG 密钥
    SECRET=$(build_mtg_secret "$RAW_SECRET" "$DOMAIN" "$TAG")
    
    echo ""
    cyan "========================================"
    cyan "  配置信息确认"
    cyan "========================================"
    blue "  端口: $PORT"
    blue "  伪装域名: $DOMAIN"
    blue "  原始密钥: $RAW_SECRET"
    if [[ -n $TAG ]]; then
        blue "  频道标签: $TAG"
    fi
    blue "  完整密钥: $SECRET"
    cyan "========================================"
    echo ""
}

# ============================================
# 生成配置文件
# ============================================

generate_config() {
    yellow "正在生成配置文件..."
    
    cat > "$CONFIG_FILE" <<EOF
# MTG Proxy 配置文件
# 完整配置文档: https://github.com/9seconds/mtg/blob/master/example.config.toml

secret = "$SECRET"
bind-to = "$BIND_TO:$PORT"
concurrency = $CONCURRENCY
tcp-buffer = "$TCP_BUFFER"
prefer-ip = "prefer-ipv4"
domain-fronting-port = 443
tolerate-time-skewness = "60s"

[network]
doh-ip = "$DOH_IP"

[network.timeout]
tcp = "$TIMEOUT_TCP"
http = "$TIMEOUT_HTTP"
idle = "$TIMEOUT_IDLE"

[defense.anti-replay]
enabled = true
max-size = "1mib"
error-rate = 0.001

[defense.blocklist]
enabled = true
download-concurrency = 2
urls = [
    "$BLOCKLIST_URL"
]
update-each = "$BLOCKLIST_UPDATE"
EOF

    green "✓ 配置文件已生成: $CONFIG_FILE"
}

# ============================================
# 生成 systemd 服务
# ============================================

generate_service() {
    yellow "正在生成 systemd 服务..."
    
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=MTG Proxy - Telegram MTProto Proxy
Documentation=https://github.com/9seconds/mtg
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=5
StartLimitInterval=0

User=root
Group=root

ExecStart=$BINEXEC run $CONFIG_FILE

# 资源限制
LimitNOFILE=1048576
LimitNPROC=512

# 安全加固
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

# 日志配置
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mtg

[Install]
WantedBy=multi-user.target
EOF

    green "✓ systemd 服务已生成: $SERVICE_FILE"
}

# ============================================
# 启动服务
# ============================================

start_service() {
    yellow "正在启动服务..."
    
    systemctl daemon-reload
    systemctl enable mtg
    systemctl start mtg
    
    # 等待服务启动
    sleep 3
    
    if systemctl is-active --quiet mtg; then
        green "✓ 服务启动成功"
    else
        red "✗ 服务启动失败"
        red "请查看日志: journalctl -u mtg -n 50"
        exit 1
    fi
}

# ============================================
# 获取服务器 IP
# ============================================

get_server_ip() {
    local ipv4
    local ipv6
    
    # 获取 IPv4
    ipv4=$(wget -qO- -4 --timeout=5 https://api.ipify.org 2>/dev/null || \
           wget -qO- -4 --timeout=5 http://ipv4.icanhazip.com 2>/dev/null || \
           curl -s -4 --max-time 5 https://api.ipify.org 2>/dev/null || \
           echo "")
    
    # 获取 IPv6
    ipv6=$(wget -qO- -6 --timeout=5 https://api6.ipify.org 2>/dev/null || \
           wget -qO- -6 --timeout=5 http://ipv6.icanhazip.com 2>/dev/null || \
           curl -s -6 --max-time 5 https://api6.ipify.org 2>/dev/null || \
           echo "")
    
    echo "$ipv4|$ipv6"
}

# ============================================
# 显示代理链接信息
# ============================================

show_proxy_links() {
    local config_file=$1
    
    # 获取服务器 IP
    local ips
    ips=$(get_server_ip)
    local ipv4=$(echo "$ips" | cut -d'|' -f1)
    local ipv6=$(echo "$ips" | cut -d'|' -f2)
    
    # 从配置文件读取信息
    local secret=$(grep "^secret" "$config_file" | cut -d'"' -f2)
    local bind_to=$(grep "^bind-to" "$config_file" | cut -d'"' -f2)
    local port=$(echo "$bind_to" | cut -d':' -f2)
    
    echo ""
    cyan "【Telegram 代理链接】"
    echo ""
    
    # IPv4 信息
    if [[ -n $ipv4 ]]; then
        blue "IPv4 代理信息："
        echo "  IP: $ipv4"
        echo "  Port: $port"
        echo "  Secret (HEX): $secret"
        echo "  TG URL: https://t.me/proxy?server=$ipv4&port=$port&secret=$secret"
        echo ""
    fi
    
    # IPv6 信息
    if [[ -n $ipv6 ]]; then
        blue "IPv6 代理信息："
        echo "  IP: $ipv6"
        echo "  Port: $port"
        echo "  Secret (HEX): $secret"
        echo "  TG URL: https://t.me/proxy?server=$ipv6&port=$port&secret=$secret"
        echo ""
    fi
    
    # 如果都获取失败
    if [[ -z $ipv4 ]] && [[ -z $ipv6 ]]; then
        yellow "无法自动获取服务器 IP，请手动构建链接："
        echo "  Port: $port"
        echo "  Secret (HEX): $secret"
        echo "  TG URL: https://t.me/proxy?server=YOUR_IP&port=$port&secret=$secret"
        echo ""
    fi
}

# ============================================
# 显示访问信息
# ============================================

show_info() {
    clear
    echo ""
    green "========================================"
    green "  MTG Proxy 安装成功！"
    green "========================================"
    echo ""
    
    # 显示服务状态
    cyan "【服务状态】"
    systemctl status mtg --no-pager -l | head -n 10
    echo ""
    
    # 显示代理链接
    show_proxy_links "$CONFIG_FILE"
    
    # 显示配置信息
    cyan "【配置信息】"
    blue "  端口: $PORT"
    blue "  伪装域名: $DOMAIN"
    blue "  原始密钥: $RAW_SECRET"
    if [[ -n $TAG ]]; then
        blue "  频道标签: $TAG"
    fi
    echo ""
    
    # 显示管理命令
    cyan "========================================"
    cyan "  管理命令"
    cyan "========================================"
    blue "  查看状态: systemctl status mtg"
    blue "  启动服务: systemctl start mtg"
    blue "  停止服务: systemctl stop mtg"
    blue "  重启服务: systemctl restart mtg"
    blue "  查看日志: journalctl -u mtg -f"
    blue "  查看链接: mtg access $CONFIG_FILE"
    echo ""
    cyan "========================================"
    cyan "  卸载命令"
    cyan "========================================"
    blue "  systemctl stop mtg"
    blue "  systemctl disable mtg"
    blue "  rm -f $BINEXEC"
    blue "  rm -f $SERVICE_FILE"
    blue "  rm -f $CONFIG_FILE"
    blue "  systemctl daemon-reload"
    cyan "========================================"
    echo ""
    green "安装完成！请将上面的链接添加到 Telegram 客户端"
    echo ""
}

# ============================================
# 升级模式
# ============================================

upgrade_mode() {
    yellow "\n检测到现有配置，进入升级模式..."
    yellow "将保留现有配置，仅升级 MTG 二进制文件\n"
    
    read -p "$(yellow '是否继续升级？[Y/n]: ')" confirm
    confirm=${confirm:-Y}
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        yellow "已取消升级"
        exit 0
    fi
    
    install_mtg
    
    yellow "重启服务..."
    systemctl restart mtg
    
    sleep 3
    
    if systemctl is-active --quiet mtg; then
        green "\n✓ 升级成功！"
        cyan "\n当前版本: $("$BINEXEC" --version 2>&1 | head -n1)"
        echo ""
        
        # 显示代理链接
        show_proxy_links "$CONFIG_FILE"
    else
        red "\n✗ 服务启动失败，请检查日志"
        red "查看日志: journalctl -u mtg -n 50"
        exit 1
    fi
}

# ============================================
# 主函数
# ============================================

main() {
    clear
    echo ""
    green "========================================"
    green "  MTG Proxy 一键安装脚本"
    green "========================================"
    green "  MTG: https://github.com/9seconds/mtg"
    green "  适用: Ubuntu 24.04 LTS x64"
    green "========================================"
    echo ""
    
    # 系统检查
    check_system
    
    # 检查是否已安装
    if [[ -f $CONFIG_FILE ]]; then
        upgrade_mode
        exit 0
    fi
    
    # 全新安装
    install_mtg
    get_user_input
    generate_config
    generate_service
    start_service
    show_info
}

# ============================================
# 脚本入口
# ============================================

main "$@"
