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

BOOTSTRAP_VERSION="v2-2026-11-15"
REPO_OWNER="${REPO_OWNER:-Program-Y}"
REPO_NAME="${REPO_NAME:-menedzher-zapret-dlya-forkop}"
BRANCH="${BRANCH:-main}"
ARCHIVE="https://codeload.github.com/${REPO_OWNER}/${REPO_NAME}/tar.gz/refs/heads/${BRANCH}"
TMP="/tmp/forkop-zapret-install"

step() {
    echo ""
    echo "[$1] $2"
}

echo "=================================================="
echo " Установщик «Менеджер Zapret для Forkop»"
echo " Bootstrap $BOOTSTRAP_VERSION"
echo "=================================================="

# Временно форсируем IPv4 (на части роутеров wget/opkg висят на IPv6)
IPV6_DISABLED=0
if [ -w /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null && IPV6_DISABLED=1
fi
restore_ipv6() {
    [ "$IPV6_DISABLED" = "1" ] && echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null
}
trap restore_ipv6 EXIT INT TERM

step "1/6" "Подготовка каталога"
echo "    Каталог: $TMP"
rm -rf "$TMP"
mkdir -p "$TMP" || { echo "    [x] Не удалось создать $TMP"; exit 1; }

step "2/6" "Скачивание архива репозитория"
echo "    URL:  $ARCHIVE"
echo "    Файл: $TMP/repo.tar.gz"
download_ok=0
if command -v wget >/dev/null 2>&1; then
    echo "    Использую wget (с прогрессом):"
    if wget -O "$TMP/repo.tar.gz" "$ARCHIVE"; then
        download_ok=1
    else
        echo "    [!] wget не смог скачать архив."
    fi
fi
if [ "$download_ok" = "0" ] && command -v curl >/dev/null 2>&1; then
    echo "    Использую curl:"
    if curl -fsSL -o "$TMP/repo.tar.gz" "$ARCHIVE"; then
        download_ok=1
    else
        echo "    [!] curl не смог скачать архив."
    fi
fi
if [ "$download_ok" = "0" ]; then
    echo "    [x] Не удалось скачать архив репозитория."
    echo "        URL: $ARCHIVE"
    echo "        Проверьте интернет и DNS."
    exit 1
fi

step "3/6" "Проверка архива"
if [ ! -s "$TMP/repo.tar.gz" ]; then
    echo "    [x] Файл пуст."
    exit 1
fi
SIZE=$(wc -c < "$TMP/repo.tar.gz" 2>/dev/null)
echo "    Размер: $SIZE байт"
if ! tar -tzf "$TMP/repo.tar.gz" >/dev/null 2>&1; then
    echo "    [x] Архив повреждён (не tar.gz)."
    exit 1
fi
echo "    Архив корректный."

step "4/6" "Распаковка"
tar -xzf "$TMP/repo.tar.gz" -C "$TMP" || { echo "    [x] Ошибка распаковки."; exit 1; }
DIR=$(find "$TMP" -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -n1)
if [ -z "$DIR" ]; then
    echo "    [x] Не найден каталог репозитория."
    exit 1
fi
echo "    Каталог: $DIR"
echo "    Содержимое:"
ls -l "$DIR" | head -n 12

step "5/6" "Запуск установщика"
echo "    Команда: sh install/install-forkop-zapret.sh"
cd "$DIR" || { echo "    [x] Не удалось перейти в $DIR"; exit 1; }
sh install/install-forkop-zapret.sh
RC=$?

step "6/6" "Завершение"
echo "    Код установщика: $RC"
exit "$RC"
