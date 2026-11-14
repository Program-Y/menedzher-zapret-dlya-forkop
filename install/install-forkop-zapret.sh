#!/bin/sh
# Полная установка: Forkop (install-forkop.sh) + расширение zapret+forkop (install-addon.sh).
# Запускать на роутере из корня репозитория: sh install/install-forkop-zapret.sh
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

echo "=================================================="
echo "   Установка Forkop + расширение zapret+forkop"
echo "=================================================="

sh "$SCRIPT_DIR/install-forkop.sh"
sh "$SCRIPT_DIR/install-addon.sh"

echo "=================================================="
echo "[+] Готово."
echo "[i] Откройте LuCI → Services → Forkop + Zapret."
echo "=================================================="
