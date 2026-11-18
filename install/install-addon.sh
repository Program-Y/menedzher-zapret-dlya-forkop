#!/bin/sh
# Установка расширения forkop-zapret (LuCI + RPCD + скрипты).
# Запускать на роутере из корня репозитория: sh install/install-addon.sh
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(dirname "$SCRIPT_DIR")
ADDON="$REPO_DIR/addon"
CONFIG="$REPO_DIR/config"

echo "[-] Установка расширения forkop-zapret..."

mkdir -p /usr/libexec/forkop-zapret /usr/libexec/rpcd
mkdir -p /www/luci-static/resources/view/forkop-zapret
mkdir -p /usr/share/luci/menu.d /usr/share/rpcd/acl.d

cp "$ADDON/runner.sh" /usr/libexec/forkop-zapret/runner.sh
cp "$ADDON/parser.sh" /usr/libexec/forkop-zapret/parser.sh
cp "$ADDON/check.sh" /usr/libexec/forkop-zapret/check.sh
chmod +x /usr/libexec/forkop-zapret/runner.sh /usr/libexec/forkop-zapret/parser.sh /usr/libexec/forkop-zapret/check.sh

cp "$ADDON/rpcd/forkop.zapret" /usr/libexec/rpcd/forkop.zapret
chmod +x /usr/libexec/rpcd/forkop.zapret

cp "$ADDON/view/forkop-zapret/main.js" /www/luci-static/resources/view/forkop-zapret/main.js
cp "$ADDON/menu.d/luci-app-forkop-zapret.json" /usr/share/luci/menu.d/luci-app-forkop-zapret.json
cp "$ADDON/acl.d/luci-app-forkop-zapret.json" /usr/share/rpcd/acl.d/luci-app-forkop-zapret.json

# Конфиги расширения — только если ещё нет (не перетираем пользовательские)
[ -f /etc/config/forkop_zapret ] || cp "$CONFIG/forkop_zapret" /etc/config/forkop_zapret
[ -f /etc/forkop_zapret.conf ] || cp "$CONFIG/forkop_zapret.conf" /etc/forkop_zapret.conf

rm -rf /tmp/luci-modulecache /tmp/luci-indexcache 2>/dev/null
if [ "${FZ_ADDON_UPDATE:-0}" != "1" ]; then
    /etc/init.d/rpcd restart 2>/dev/null || true
    /etc/init.d/uhttpd restart 2>/dev/null || true
fi

echo "[+] Расширение установлено."
