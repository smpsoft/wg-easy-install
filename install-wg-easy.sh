#!/bin/bash
# WG-Easy host模式一键部署脚本，自动获取公网IP，端口可自定义
set -euo pipefail

REQUIRED_KERNEL="5.6"
WG_DEFAULT_ADDRESS="10.0.9.x"
WG_DEFAULT_DNS="168.126.63.1,8.8.8.8"
WG_ALLOWED_IPS="0.0.0.0/0"
WG_PERSISTENT_KEEPALIVE=25
CONTAINER_NAME="wg-easy"
VOLUME_PATH="$HOME/.wg-easy"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 内核检测
kernel_ver=$(uname -r | cut -d. -f1,2)
if awk -v k="$kernel_ver" -v t="$REQUIRED_KERNEL" 'BEGIN{if(k<t)exit 1;else exit 0}';then
    echo -e "${GREEN}[OK] 内核 $kernel_ver ✔${NC}"
else
    echo -e "${RED}[ERROR] 内核版本过低，最低需要 ${REQUIRED_KERNEL}${NC}"
    exit 1
fi

# 安装依赖
check_dep(){
    if ! command -v "$1" &>/dev/null;then
        echo -e "${RED}[INFO] $1 未安装，正在安装${NC}"
        apt update -y && apt install -y "$1"
    fi
}
check_dep curl

# 自动安装docker
if ! command -v docker &>/dev/null;then
    echo -e "${GREEN}[INFO] 安装Docker${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable --now docker
    usermod -aG docker root
    sleep 2
fi

# 自动模式判断：必须有 WG_HOST WG_PORT PORT WG_PASSWORD_HASH
AUTO_MODE=0
if [[ -n "${WG_HOST:-}" && -n "${WG_PORT:-}" && -n "${PORT:-}" && -n "${WG_PASSWORD_HASH:-}" ]];then
    AUTO_MODE=1
    ipv4="$WG_HOST"
    wg_port="$WG_PORT"
    web_port="$PORT"
    pass_hash="$WG_PASSWORD_HASH"
else
    echo -e "${RED}[ERROR] 缺少环境变量，仅支持传入环境变量全自动部署${NC}"
    exit 1
fi

# 清理旧资源
echo -e "${GREEN}[INFO] 清理旧容器和旧配置目录${NC}"
if docker ps -a --filter "name=^/${CONTAINER_NAME}$" | grep -q "$CONTAINER_NAME";then
    docker rm -f "$CONTAINER_NAME"
fi
rm -rf "$VOLUME_PATH"

# 汇总信息
echo -e "\n==================== 配置汇总 ===================="
echo "WG_HOST:        $ipv4"
echo "WG_PORT(UDP):   $wg_port"
echo "Web面板端口:    $web_port"
echo "网段:           $WG_DEFAULT_ADDRESS"
echo "=================================================="
if [[ $AUTO_MODE -eq 1 ]];then
    echo "[AUTO MODE] 全自动部署，跳过确认"
else
    read -p "确认继续部署？(y/n)" ans
    [[ "$ans" != "y" ]] && echo "退出" && exit 0
fi

# host模式启动，和你可用配置完全一致
echo -e "${GREEN}[INFO] 启动 wg-easy --net=host${NC}"
docker run -d \
  --name="$CONTAINER_NAME" \
  --net=host \
  -e WG_HOST="$ipv4" \
  -e WG_PORT="$wg_port" \
  -e PORT="$web_port" \
  -e WG_DEFAULT_ADDRESS="$WG_DEFAULT_ADDRESS" \
  -e WG_DEFAULT_DNS="$WG_DEFAULT_DNS" \
  -e WG_ALLOWED_IPS="$WG_ALLOWED_IPS" \
  -e WG_PERSISTENT_KEEPALIVE="$WG_PERSISTENT_KEEPALIVE" \
  -e PASSWORD_HASH="$pass_hash" \
  -e INSECURE=true \
  -v "$VOLUME_PATH:/etc/wireguard" \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  --restart unless-stopped \
  ghcr.io/wg-easy/wg-easy

if [ $? -ne 0 ];then
    echo -e "${RED}[ERROR] 容器启动失败${NC}"
    exit 1
fi

echo -e "\n${GREEN}[SUCCESS] 部署完成！${NC}"
echo "面板地址：http://$ipv4:$web_port"
echo "WireGuard端口：$wg_port/udp"
echo "记得在云服务商安全组放行以上端口！"
