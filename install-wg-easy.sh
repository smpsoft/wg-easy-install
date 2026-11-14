#!/bin/bash
# WG-Easy 一键部署脚本，支持全自动模式（环境变量） / 交互式
# Usage:
# 【交互模式】bash install-wg-easy.sh
# 【全自动模式】
# WG_HOST=45.154.14.62 WG_WEB_PORT=32083 WG_PASSWORD="MyPass123" bash install-wg-easy.sh

set -euo pipefail

REQUIRED_KERNEL="5.6"
WG_DEFAULT_PORT=51820
WG_DEFAULT_CIDR="10.0.8.x"
WG_DEFAULT_DNS="168.126.63.1,8.8.8.8"
WG_ALLOWED_IPS="0.0.0.0/1,128.0.0.0/1"
WG_PERSISTENT_KEEPALIVE=25
CONTAINER_NAME="wg-easy"
VOLUME_PATH="$HOME/.wg-easy"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

version_ge() {
    printf '%s\n' "$1" "$2" | sort -V | head -n1 | grep -q "^$2"
}

check_dep() {
    if ! command -v "$1" &>/dev/null; then
        echo -e "${RED}[ERROR] $1 未安装，正在安装...${NC}"
        apt update && apt install -y "$1"
    fi
}

# 自动安装 docker（全自动最关键：没有docker就自动装）
install_docker() {
    if ! command -v docker &>/dev/null; then
        echo -e "${GREEN}[INFO] 检测不到Docker，自动安装Docker${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable --now docker
        usermod -aG docker "$USER"
        sleep 2
    fi
}

# 内核检查
kernel_version=$(uname -r)
if version_ge "$kernel_version" "$REQUIRED_KERNEL"; then
    echo -e "${GREEN}[OK] 内核 $kernel_version ✔${NC}"
else
    echo -e "${RED}[ERROR] 内核 $kernel_version，最低要求 $REQUIRED_KERNEL${NC}"
    exit 1
fi

check_dep curl
install_docker

# -------------------------- 自动模式判断：环境变量是否存在 --------------------------
AUTO_MODE=0
if [[ -n "${WG_HOST:-}" && -n "${WG_PASSWORD:-}" && -n "${WG_WEB_PORT:-}" ]]; then
    AUTO_MODE=1
    ipv4="$WG_HOST"
    TCP_PORT="$WG_WEB_PORT"
    PASSWORD="$WG_PASSWORD"
else
    # ===== 交互模式（原来的逻辑）=====
    read -p "是否自动获取公网IPv4？（y/n）" use_auto_ip
    if [[ "$use_auto_ip" =~ ^[Yy]$ ]]; then
        echo "[INFO] 获取公网IP..."
        ipv4=$(curl -s --connect-timeout 5 https://ipv4.icanhazip.com | tr -d '\n')
        if [[ -z "$ipv4" ]]; then
            echo -e "${RED}[ERROR] 获取IP失败，请手动输入${NC}"
            read -p "IPv4/域名: " ipv4
        else
            echo "获取IP: $ipv4"
            read -p "使用该IP？(y/n)" use_auto_ip_result
            if [[ "$use_auto_ip_result" =~ ^[Nn]$ ]]; then
                read -p "IPv4/域名: " ipv4
            fi
        fi
    else
        read -p "IPv4或者域名: " ipv4
    fi

    read -p "管理后台密码: " -s PASSWORD
    echo
    if [[ -z "$PASSWORD" ]]; then
        echo -e "${RED}[ERROR] 密码不能为空${NC}"
        exit 1
    fi

    read -p "管理后台TCP端口: " TCP_PORT
    if [[ -z "$TCP_PORT" ]]; then
        echo -e "${RED}[ERROR] 端口不能为空${NC}"
        exit 1
    fi
fi

# 生成密码hash
PASSWORD_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy wgpw "$PASSWORD")

# 汇总
echo -e "\n==================== 配置汇总 ===================="
echo "WG_HOST:        $ipv4"
echo "WireGuard端口:  $WG_DEFAULT_PORT/udp"
echo "Web面板端口:    $TCP_PORT/tcp"
echo "WG地址段:       $WG_DEFAULT_CIDR"
echo "=================================================="

# 自动模式跳过确认；交互模式需要确认
if [[ $AUTO_MODE -eq 0 ]]; then
    read -p "确认继续部署？(y/n)" answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo "退出"
        exit 0
    fi
else
    echo "[AUTO MODE] 全自动部署，跳过确认"
fi

# 删除旧容器
if docker ps -a --filter "name=^/${CONTAINER_NAME}$" | grep -q "$CONTAINER_NAME"; then
    echo "[INFO] 删除旧容器 $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME"
fi

# 启动容器
echo "[INFO] 启动 wg-easy"
docker run -d \
  --name="$CONTAINER_NAME" \
  -e WG_HOST="$ipv4" \
  -e WG_PORT="$WG_DEFAULT_PORT" \
  -e PORT="$TCP_PORT" \
  -e WG_DEFAULT_ADDRESS="$WG_DEFAULT_CIDR" \
  -e WG_DEFAULT_DNS="$WG_DEFAULT_DNS" \
  -e WG_ALLOWED_IPS="$WG_ALLOWED_IPS" \
  -e WG_PERSISTENT_KEEPALIVE="$WG_PERSISTENT_KEEPALIVE" \
  -e PASSWORD_HASH="$PASSWORD_HASH" \
  -e INSECURE=true \
  -v "$VOLUME_PATH:/etc/wireguard" \
  -p "${WG_DEFAULT_PORT}:${WG_DEFAULT_PORT}/udp" \
  -p "${TCP_PORT}:${TCP_PORT}/tcp" \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  --restart unless-stopped \
  ghcr.io/wg-easy/wg-easy

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR] 容器启动失败${NC}"
    exit 1
fi

echo -e "\n${GREEN}[SUCCESS] 部署完成！${NC}"
echo "👉 面板地址：http://$ipv4:$TCP_PORT"
echo "👉 WireGuard：$WG_DEFAULT_PORT/udp"
echo "👉 数据目录：$VOLUME_PATH"
echo "⚠️  放行安全组：$WG_DEFAULT_PORT/udp 、$TCP_PORT/tcp"
