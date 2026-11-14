# 先安装git
apt install git -y
# 克隆仓库，替换成你自己仓库地址
git clone https://github.com/smpsoft/wg-easy-install.git
cd wg-easy-install
# 把脚本放进这个文件夹
cp /root/install-wg-easy.sh ./
git add .
git commit -m "add install script"
git push
