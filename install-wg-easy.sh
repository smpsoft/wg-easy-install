#!/bin/bash
#
# WG-Easy Install Script
# Source: https://github.com/你的用户名/你的仓库名
# Usage: bash install-wg-easy.sh
#

set -euo pipefail

# -------------------------- 配置常量 --------------------------
REQUIRED_KERNEL="5.6"
WG_DEFAULT_PORT=51820
WG_DEFAULT_CIDR="10.0.8.x"
WG_DEFAULT_DNS="168.126.63.1,8.8.8.8"
WG_ALLOWED_IPS="0.0.0.0/1,128.0.0.0/1"
WG_PERSISTENT_KEEPALIVE=25
CONTAINER_NAME="wg-easy"
VOLUME_PATH="$HOME/.wg-easy"

# -------------------------- 颜色定义 --------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# -------------------------- 函数：版本比较 --------------------------
version_ge() {
    # $1 >= $2 返回0
    printf '%s\n' "$1" "$2" | sort -V | head -n1 | grep -q "^$2"
}

# -------------------------- 前置依赖检查 --------------------------
check_dep() {
    if ! command -v "$1" &>/dev/null; then
        echo -e "${RED}[ERROR] $1 未安装，请先安装 $1${NC}"
        exit 1
    fi
}

check_dep curl
check_dep docker

# -------------------------- 内核版本校验 --------------------------
kernel_version=$(uname -r)
if version_ge "$kernel_version" "$REQUIRED_KERNEL"; then
    echo -e "${GREEN}[OK] 当前内核版本: $kernel_version (≥$REQUIRED_KERNEL)${NC}"
else
    echo -e "${RED}[ERROR] 当前内核版本: $kernel_version，最低要求 $REQUIRED_KERNEL${NC}"
    exit 1
fi

# -------------------------- 公网IP获取 --------------------------
read -p "是否自动获取公网IPv4？（y/n）" use_auto_ip
if [[ "$use_auto_ip" =~ ^[Yy]$ ]]; then
    echo "[INFO] 正在获取公网IP..."
    ipv4=$(curl -s --connect-timeout 5 https://ipv4.icanhazip.com | tr -d '\n')
    if [[ -z "$ipv4" ]]; then
        echo -e "${RED}[ERROR] 获取公网IP失败，请手动输入${NC}"
        read -p "请输入IPv4地址或者域名: " ipv4
    else
        echo "获取到IP: $ipv4"
        read -p "是否使用该IP？（y/n）" use_auto_ip_result
        if [[ "$use_auto_ip_result" =~ ^[Nn]$ ]]; then
            read -p "请输入IPv4地址或者域名: " ipv4
        fi
    fi
else
    read -p "请输入IPv4地址或者域名: " ipv4
fi

# -------------------------- 面板密码，自动生成PASSWORD_HASH --------------------------
read -p "请输入管理后台密码: " -s PASSWORD
echo
if [[ -z "$PASSWORD" ]]; then
    echo -e "${RED}[ERROR] 密码不能为空${NC}"
    exit 1
fi
# 用docker内wg-easy自带工具生成bcrypt hash
PASSWORD_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy wgpw "$PASSWORD")

# -------------------------- Web面板端口 --------------------------
read -p "请输入管理后台访问端口(TCP): " TCP_PORT
if [[ -z "$TCP_PORT" ]]; then
    echo -e "${RED}[ERROR] 面板端口不能为空${NC}"
    exit 1
fi

# -------------------------- 汇总确认 --------------------------
echo -e "\n==================== 配置汇总 ===================="
echo "WG_HOST:        $ipv4"
echo "WireGuard端口:  $WG_DEFAULT_PORT/udp"
echo "Web面板端口:    $TCP_PORT/tcp"
echo "WG地址段:       $WG_DEFAULT_CIDR"
echo "=================================================="
read -p "确认继续部署？(y/n)" answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "退出脚本"
    exit 0
fi

# -------------------------- 容器存在则清理旧容器 --------------------------
if docker ps -a --filter "name=^/${CONTAINER_NAME}$" | grep -q "$CONTAINER_NAME"; then
    echo "[INFO] 发现旧容器 $CONTAINER_NAME，正在删除..."
    docker rm -f "$CONTAINER_NAME"
fi

# -------------------------- 启动 wg-easy --------------------------
echo "[INFO] 启动 wg-easy 容器..."
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
    echo -e "${RED}[ERROR] 容器启动失败！${NC}"
    exit 1
fi

# -------------------------- 输出信息 --------------------------
echo -e "\n${GREEN}[SUCCESS] WG-Easy 部署完成！${NC}"
echo "----------------------------------------"
echo "👉 管理面板地址：http://$ipv4:$TCP_PORT"
echo "👉 WireGuard 端口：$WG_DEFAULT_PORT/udp"
echo "👉 数据持久化目录：$VOLUME_PATH"
echo "⚠️  记得在云服务商安全组/防火墙放行："
echo "    $WG_DEFAULT_PORT/udp  和  $TCP_PORT/tcp"
echo "----------------------------------------"
