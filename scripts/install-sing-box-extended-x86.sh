#!/bin/sh
# Установка extended sing-box на x86_64 (OpenWrt), если в фидах нет пакета.
# Запускать на роутере: sh scripts/install-sing-box-extended-x86.sh
set -e

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ;;
  *) echo "[x] Этот скрипт для x86_64. Текущая архитектура: $ARCH"; exit 1 ;;
esac

echo "[-] Пробуем штатный пакет sing-box-extended из фидов..."
if opkg install --force-overwrite sing-box-extended 2>/dev/null; then
    echo "[+] Установлен sing-box-extended из фидов."
    exit 0
fi

VER="${SING_BOX_VERSION:-1.14.3}"
TMP="/tmp/sing-box-extended"
rm -rf "$TMP"; mkdir -p "$TMP"

# Официальные сборки SagerNet (extended)
URL="https://github.com/SagerNet/sing-box/releases/download/v${VER}/sing-box-${VER}-linux-amd64.tar.gz"
echo "[-] Скачивание $URL ..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$TMP/sb.tar.gz" "$URL" || wget -q --no-check-certificate -O "$TMP/sb.tar.gz" "$URL"
else
    wget -q --no-check-certificate -O "$TMP/sb.tar.gz" "$URL"
fi

tar -xzf "$TMP/sb.tar.gz" -C "$TMP" 2>/dev/null || { echo "[x] Не удалось распаковать архив"; exit 1; }
BIN=$(find "$TMP" -type f -name sing-box | head -n1)
[ -z "$BIN" ] && { echo "[x] В архиве не найден sing-box"; exit 1; }

/etc/init.d/sing-box stop 2>/dev/null || true
cp "$BIN" /usr/bin/sing-box
chmod +x /usr/bin/sing-box
[ -d /etc/forkop ] && echo "extended" > /etc/forkop/sing-box-variant
echo "[+] Установлено: $(/usr/bin/sing-box version 2>/dev/null | head -n1)"
/etc/init.d/forkop restart 2>/dev/null || true
rm -rf "$TMP"
