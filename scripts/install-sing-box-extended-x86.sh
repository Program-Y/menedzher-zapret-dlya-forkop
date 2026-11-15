#!/bin/sh
# Установка sing-box-extended для OpenWrt x86_64.
# Основано на логике EikeiDev/OpenWRT-sing-box-extended (сборки shtorm-7/sing-box-extended).
# Запускать на роутере: sh scripts/install-sing-box-extended-x86.sh
set -e

[ -f /etc/openwrt_release ] && . /etc/openwrt_release
ARCH="${DISTRIB_ARCH:-$(uname -m)}"
case "$ARCH" in
    x86_64|amd64) ;;
    *) echo "[x] Этот скрипт для x86_64. Текущая архитектура: $ARCH"; exit 1 ;;
esac

API="https://api.github.com/repos/shtorm-7/sing-box-extended/releases?per_page=10"
TMP="/tmp/sing-box-extended-x86"
DEST="/usr/bin/sing-box"
VARIANT_MARKER="/etc/forkop/sing-box-variant"
VERSION_STATE="/etc/forkop/sing-box-version"

fail() {
    echo "[x] $1"
    rm -rf "$TMP"
    exit 1
}

echo "[-] Архитектура: $ARCH (x86_64)"
echo "[-] Запрос релизов shtorm-7/sing-box-extended..."
JSON=""
if command -v curl >/dev/null 2>&1; then
    JSON=$(curl -4 -fsSL --connect-timeout 10 --max-time 60 "$API" 2>/dev/null) || true
fi
if [ -z "$JSON" ] && command -v wget >/dev/null 2>&1; then
    JSON=$(wget -T 30 -qO- "$API" 2>/dev/null) || true
fi
[ -z "$JSON" ] && fail "Не удалось получить список релизов GitHub."
command -v jsonfilter >/dev/null 2>&1 || fail "Нет jsonfilter (нужен для разбора релизов)."

TAG=""
URL=""
i=0
while [ "$i" -lt 10 ]; do
    T=$(echo "$JSON" | jsonfilter -e "@[$i].tag_name" 2>/dev/null)
    [ -z "$T" ] && break
    case "$T" in
        *rc*|*RC*|*beta*|*BETA*|*alpha*|*ALPHA*) i=$((i + 1)); continue ;;
    esac
    U=$(echo "$JSON" | jsonfilter -e "@[$i].assets[*].browser_download_url" 2>/dev/null | grep -E 'linux-amd64\.tar\.gz$' | grep -v 'compressed' | head -n1)
    if [ -n "$U" ]; then
        TAG="$T"
        URL="$U"
        break
    fi
    i=$((i + 1))
done
[ -z "$URL" ] && fail "Не найден linux-amd64.tar.gz в стабильных релизах."

echo "[-] Версия: $TAG"
echo "[-] Файл:  $URL"
rm -rf "$TMP"
mkdir -p "$TMP"

echo "[-] Скачивание..."
DL_OK=0
if command -v curl >/dev/null 2>&1; then
    if curl -4 -fL --connect-timeout 10 --max-time 300 --retry 2 -o "$TMP/sb.tar.gz" "$URL"; then
        DL_OK=1
    else
        echo "[!] curl: ошибка скачивания, пробую wget..."
    fi
fi
if [ "$DL_OK" = "0" ] && command -v wget >/dev/null 2>&1; then
    if wget -T 30 -O "$TMP/sb.tar.gz" "$URL"; then
        DL_OK=1
    else
        echo "[!] wget: ошибка скачивания"
    fi
fi
[ "$DL_OK" = "1" ] || fail "Не удалось скачать sing-box-extended."
SIZE=$(wc -c < "$TMP/sb.tar.gz" 2>/dev/null)
echo "    Размер: $SIZE байт"
[ -s "$TMP/sb.tar.gz" ] || fail "Скачанный файл пуст."
tar -tzf "$TMP/sb.tar.gz" >/dev/null 2>&1 || fail "Архив повреждён (не tar.gz)."
tar -xzf "$TMP/sb.tar.gz" -C "$TMP" || fail "Ошибка распаковки."
BIN_SRC=$(find "$TMP" -type f -name sing-box | head -n1)
[ -z "$BIN_SRC" ] && fail "В архиве не найден sing-box."

echo "[-] Остановка сервисов..."
/etc/init.d/sing-box stop 2>/dev/null || true
/etc/init.d/forkop stop 2>/dev/null || true
killall sing-box 2>/dev/null || true

echo "[-] Установка $DEST..."
cp "$BIN_SRC" "$DEST" || fail "Не удалось скопировать бинарник в $DEST."
chmod +x "$DEST"
NEW_VER=$("$DEST" version 2>/dev/null | head -n1 | awk '{print $NF}')
echo "[-] Версия бинарника: ${NEW_VER:-неизвестно}"

# Маркеры для Forkop
mkdir -p /etc/forkop 2>/dev/null
echo "extended" > "$VARIANT_MARKER" 2>/dev/null || true
[ -n "$NEW_VER" ] && echo "$NEW_VER" > "$VERSION_STATE" 2>/dev/null || true

# Сервис, если Forkop ещё не создал (совместим с Forkop-маркером)
if [ ! -f /etc/init.d/sing-box ]; then
    cat > /etc/init.d/sing-box <<'EOF'
#!/bin/sh /etc/rc.common
# Forkop managed sing-box service for binary variants
START=99
STOP=10
USE_PROCD=1
PROG="/usr/bin/sing-box"
start_service() {
    config_load "sing-box"
    config_get config_file "main" "conffile" "/etc/sing-box/config.json"
    config_get working_directory "main" "workdir" "/usr/share/sing-box"
    procd_open_instance
    procd_set_param command "$PROG" run -c "$config_file" -D "$working_directory"
    procd_set_param respawn
    procd_set_param file "$config_file"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
    chmod +x /etc/init.d/sing-box
fi
chmod +x /etc/init.d/sing-box
/etc/init.d/sing-box enable 2>/dev/null || true

rm -rf "$TMP"
echo "[+] sing-box-extended x86_64 установлен: ${NEW_VER:-неизвестно}"
echo "[i] Запуск выполнит Forkop (после добавления ключа/подписки в main_vpn)."
