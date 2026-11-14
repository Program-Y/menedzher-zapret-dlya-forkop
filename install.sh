#!/bin/sh
# Bootstrap-установщик «Менеджер Zapret для Forkop».
#
# Одна команда (OpenWrt/busybox ash и bash):
#   wget -O - https://raw.githubusercontent.com/Program-Y/menedzher-zapret-dlya-forkop/main/install.sh | sh
#
# Для bash также работает:
#   sh <(wget -O - https://raw.githubusercontent.com/Program-Y/menedzher-zapret-dlya-forkop/main/install.sh)
#
# Неинтерактивно: ... | ASSUME_YES=1 sh
set -e

REPO_OWNER="${REPO_OWNER:-Program-Y}"
REPO_NAME="${REPO_NAME:-menedzher-zapret-dlya-forkop}"
BRANCH="${BRANCH:-main}"
ARCHIVE="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${BRANCH}.tar.gz"

TMP="/tmp/forkop-zapret-install"
rm -rf "$TMP"
mkdir -p "$TMP"

echo "[-] Скачивание ${REPO_OWNER}/${REPO_NAME} (${BRANCH})..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$TMP/repo.tar.gz" "$ARCHIVE"
else
    wget -q -O "$TMP/repo.tar.gz" "$ARCHIVE"
fi

echo "[-] Распаковка..."
tar -xzf "$TMP/repo.tar.gz" -C "$TMP"
DIR=$(find "$TMP" -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -n1)
[ -n "$DIR" ] || { echo "[x] Не удалось распаковать архив"; exit 1; }

echo "[-] Запуск установки из $DIR ..."
cd "$DIR"
sh install/install-forkop-zapret.sh

echo "[+] Готово."
