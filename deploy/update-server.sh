#!/bin/bash
# Run on China server to pull latest build from Gitee
# Usage: sudo bash /opt/bridgeread-server/deploy/update-server.sh

set -e

echo "=== Updating frontend ==="
cd /tmp
rm -rf web-deploy
git clone -b deploy --depth 1 https://gitee.com/Yejiaomin_e351/bridge-read.git web-deploy
rm -rf /var/www/bridgeread/*
cp -r web-deploy/* /var/www/bridgeread/
rm -rf web-deploy
echo "Frontend updated."

echo "=== Updating backend ==="
cd /opt/bridgeread-server
git pull origin production
cd server
npm install --omit=dev --registry https://registry.npmmirror.com
pm2 restart bridgeread-api
echo "Backend updated."

echo "=== Reloading nginx ==="
nginx -t && systemctl reload nginx
echo "Done! All updated."
