# wg-easy-install
wg-easy 一键部署脚本，支持【交互式】和【全自动无交互部署】

### 全自动部署（推荐批量）
```bash
WG_HOST=45.154.14.xx WG_WEB_PORT=32083 WG_PASSWORD="MyPass123" curl -sL https://raw.githubusercontent.com/smpsoft/wg-easy-install/main/install-wg-easy.sh | bash 
```

### 自动获取本机公网 IP 全自动部署
```bash
export WG_HOST=$(curl -s https://ipv4.icanhazip.com | tr -d '\n')
WG_WEB_PORT=32083 WG_PASSWORD="MyPass123" curl -sL https://raw.githubusercontent.com/smpsoft/wg-easy-install/main/install-wg-easy.sh | bash
```
### 交互式部署
```
bash install-wg-easy.sh
```
