#!/bin/sh
# Полная установка: Forkop (install-forkop.sh) + расширение zapret+forkop (install-addon.sh).
# Запускать на роутере из корня репозитория: sh install/install-forkop-zapret.sh
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

echo "=================================================="
echo "   Установка Forkop + расширение zapret+forkop"
echo "=================================================="

rm -f /tmp/forkop-zapret-install-addon
FZ_WRAPPER=1 sh "$SCRIPT_DIR/install-forkop.sh"
if [ -f /tmp/forkop-zapret-install-addon ]; then
    rm -f /tmp/forkop-zapret-install-addon
    sh "$SCRIPT_DIR/install-addon.sh"
else
    echo "[i] Аддон zapret+forkop не устанавливается."
fi

if [ -f /tmp/forkop-zapret-need-key ]; then
    rm -f /tmp/forkop-zapret-need-key
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            ВАЖНО: ПЕРЕД ЗАПУСКОМ FORKOP                     ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  В конфиге НЕТ ключа или подписки для секции main_vpn.      ║"
    echo "║                                                              ║"
    echo "║  1. Откройте LuCI → Forkop → Секции → main_vpn              ║"
    echo "║  2. Добавьте подписку (URL) или ключ/ссылку на сервер        ║"
    echo "║  3. Сохраните и запустите Forkop                            ║"
    echo "║                                                              ║"
    echo "║  Без этого sing-box не подключится и будет падать.          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
fi

echo "=================================================="
echo "[+] Установка завершена."
echo "[i] Откройте LuCI и нажмите Ctrl+F5."
echo "=================================================="
