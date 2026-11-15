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

REPO_OWNER="${REPO_OWNER:-Program-Y}"
REPO_NAME="${REPO_NAME:-menedzher-zapret-dlya-forkop}"
BRANCH="${BRANCH:-main}"
ARCHIVE="https://codeload.github.com/${REPO_OWNER}/${REPO_NAME}/tar.gz/refs/heads/${BRANCH}"
TMP="/tmp/forkop-zapret-install"

# Временно форсируем IPv4 (на части роутеров wget/opkg висят на IPv6)
IPV6_DISABLED=0
if [ -w /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null && IPV6_DISABLED=1
fi
restore_ipv6() {
    [ "$IPV6_DISABLED" = "1" ] && echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null
}
trap restore_ipv6 EXIT INT TERM

echo "[-] Скачивание ${REPO_OWNER}/${REPO_NAME} (${BRANCH})..."
rm -rf "$TMP"
mkdir -p "$TMP"

download_ok=0
if command -v wget >/dev/null 2>&1; then
    echo "[-] wget $ARCHIVE"
    if wget -O "$TMP/repo.tar.gz" "$ARCHIVE"; then
        download_ok=1
    else
        echo "[!] wget не смог скачать архив."
    fi
fi
if [ "$download_ok" = "0" ] && command -v curl >/dev/null 2>&1; then
    echo "[-] curl $ARCHIVE"
    if curl -fsSL -o "$TMP/repo.tar.gz" "$ARCHIVE"; then
        download_ok=1
    else
        echo "[!] curl не смог скачать архив."
    fi
fi
if [ "$download_ok" = "0" ]; then
    echo "[x] Не удалось скачать архив репозитория."
    echo "    URL: $ARCHIVE"
    echo "    Проверьте интернет и DNS или скачайте архив вручную."
    exit 1
fi

if [ ! -s "$TMP/repo.tar.gz" ]; then
    echo "[x] Скачанный архив пуст."
    exit 1
fi
if ! tar -tzf "$TMP/repo.tar.gz" >/dev/null 2>&1; then
    echo "[x] Архив повреждён (не tar.gz)."
    exit 1
fi

echo "[-] Распаковка..."
tar -xzf "$TMP/repo.tar.gz" -C "$TMP" || { echo "[x] Ошибка распаковки."; exit 1; }
DIR=$(find "$TMP" -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -n1)
if [ -z "$DIR" ]; then
    echo "[x] Не найден каталог репозитория после распаковки."
    exit 1
fi

echo "[-] Запуск установки из $DIR ..."
cd "$DIR" || { echo "[x] Не удалось перейти в $DIR"; exit 1; }
sh install/install-forkop-zapret.sh
