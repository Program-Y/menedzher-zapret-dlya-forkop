#!/bin/sh
# Мастер-установка Forkop (+ zapret/расширение) для OpenWrt 24.10+
# Запускать на роутере: sh install/install-forkop.sh
# Переменные: ASSUME_YES=1 — не задавать вопросы; CONFIG_DIR=... — каталог с конфигами.

echo "=================================================="
echo "   Мастер-скрипт установки и очистки Forkop 1.0.5 "
echo "=================================================="

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(dirname "$SCRIPT_DIR")
CONFIG_DIR="${CONFIG_DIR:-$REPO_DIR/config}"
NEED_VPN_KEY=0

ask_yes() {
    [ "$ASSUME_YES" = "1" ] && return 0
    printf "%s [y/N]: " "$1"
    if [ -r /dev/tty ]; then
        read ans < /dev/tty
    else
        read ans
    fi
    case "$ans" in y|Y|yes|YES|да|Да) return 0 ;; *) return 1 ;; esac
}

ask_yes_d() {
    [ "$ASSUME_YES" = "1" ] && return 0
    printf "%s [Y/n]: " "$1"
    if [ -r /dev/tty ]; then
        read ans < /dev/tty
    else
        read ans
    fi
    case "$ans" in n|N|no|NO|нет|Нет) return 1 ;; *) return 0 ;; esac
}

# --- Форсирование IPv4 на время установки (иначе opkg/wget висят на IPv6) ---
disable_ipv6() {
    [ -w /proc/sys/net/ipv6/conf/all/disable_ipv6 ] && echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null
    [ -w /proc/sys/net/ipv6/conf/default/disable_ipv6 ] && echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
}

enable_ipv6() {
    [ -w /proc/sys/net/ipv6/conf/all/disable_ipv6 ] && echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null
    [ -w /proc/sys/net/ipv6/conf/default/disable_ipv6 ] && echo 0 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null
    sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
}

# --- Поиск файлов-заглушек вида "OK <pkg> -" ---
scan_stubs() {
    for d in /bin /sbin /usr/bin /usr/sbin /usr/libexec; do
        for f in "$d"/*; do
            [ -f "$f" ] || continue
            [ -L "$f" ] && continue
            if head -c 3 "$f" 2>/dev/null | grep -q '^OK '; then
                echo "$f"
            fi
        done
    done
    for f in /usr/lib/*.so* /usr/lib/lib*; do
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue
        if head -c 3 "$f" 2>/dev/null | grep -q '^OK '; then
            echo "$f"
        fi
    done
}

verify_critical() {
    local bad=0 f s
    for f in /usr/libexec/ip-full /usr/bin/curl /usr/bin/dig /usr/bin/jsonfilter /usr/sbin/nft; do
        [ -e "$f" ] || continue
        [ -L "$f" ] && continue
        s=$(wc -c < "$f" 2>/dev/null)
        if [ "${s:-0}" -lt 1000 ] || head -c 3 "$f" 2>/dev/null | grep -q '^OK '; then
            echo "[!] Повреждён: $f ($s байт)"
            bad=1
        fi
    done
    return $bad
}

repair_stub_pkgs() {
    echo "[-] Восстановление пакетов из официальных ipk..."
    disable_ipv6
    opkg update 2>/dev/null
    for pkg in ip-full curl bind-dig jsonfilter nftables; do
        echo "[-] Переустановка $pkg..."
        opkg install --force-reinstall "$pkg" 2>/dev/null || opkg install "$pkg" 2>/dev/null || echo "[!] Не удалось: $pkg"
    done
    enable_ipv6
}

# --- Единая загрузка: HTTP-проверка, прогресс, таймаут, размер ---
download() {
    local url="$1" out="$2" desc="$3"
    echo "[-] $desc"
    echo "    URL: $url"
    echo "    -> $out"
    rm -f "$out"
    local ok=0 code=""
    if command -v curl >/dev/null 2>&1; then
        code=$(curl -4 -sIL -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 "$url" 2>/dev/null)
        echo "    HTTP-проверка: ${code:-нет ответа}"
        if curl -4 -fL --connect-timeout 10 --max-time 300 --retry 2 -o "$out" "$url"; then
            ok=1
        else
            echo "    [!] curl: ошибка скачивания"
        fi
    fi
    if [ "$ok" = "0" ] && command -v wget >/dev/null 2>&1; then
        echo "    Пробую wget (таймаут 30 с)..."
        if wget -T 30 -O "$out" "$url"; then
            ok=1
        else
            echo "    [!] wget: ошибка скачивания"
        fi
    fi
    if [ "$ok" = "0" ] || [ ! -s "$out" ]; then
        echo "    [x] Не удалось скачать: $url"
        return 1
    fi
    local size
    size=$(wc -c < "$out" 2>/dev/null)
    echo "    Размер: $size байт"
    return 0
}

# --- Установка компонента через штатный Forkop (как кнопка в LuCI) ---
forkop_component() {
    local component="$1" action="$2" desc="$3"
    echo "[-] $desc"
    echo "    forkop component_action_async $component $action"
    local json job log elapsed=0 running="true" st msg success
    json=$(forkop component_action_async "$component" "$action" 2>&1)
    echo "    $json"
    job=$(echo "$json" | jsonfilter -e '@.job_id' 2>/dev/null)
    if [ -z "$job" ]; then
        echo "    [x] Не удалось создать задачу установки"
        return 1
    fi
    log="/var/run/forkop/component-actions/$job.out"
    while [ "$running" = "true" ]; do
        sleep 3
        elapsed=$((elapsed + 3))
        st=$(forkop component_action_status "$job" 2>/dev/null)
        running=$(echo "$st" | jsonfilter -e '@.running' 2>/dev/null)
        msg=$(echo "$st" | jsonfilter -e '@.message' 2>/dev/null)
        echo "    [$elapsed s] ${msg:-выполняется...}"
        [ -f "$log" ] && tail -n 2 "$log" 2>/dev/null | sed 's/^/      /'
        if [ "$elapsed" -ge 1800 ]; then
            echo "    [x] Таймаут 30 минут"
            return 1
        fi
    done
    echo "    Итог: $st"
    success=$(echo "$st" | jsonfilter -e '@.success' 2>/dev/null)
    if [ "$success" = "true" ]; then
        return 0
    fi
    echo "    [x] Ошибка установки компонента"
    [ -f "$log" ] && tail -n 30 "$log" | sed 's/^/      /'
    return 1
}

# ==================================================
# ЭТАП 0: ПРОВЕРКА ЦЕЛОСТНОСТИ СИСТЕМНЫХ ФАЙЛОВ
# ==================================================
echo "[-] Проверка целостности системных файлов (заглушки/битые бинарники)..."
STUBS=$(scan_stubs | grep -vE '/(sing-box|forkop|xray|nfqws)$')
if [ -n "$STUBS" ]; then
    echo "[!] Найдены файлы-заглушки:"
    echo "$STUBS" | sed 's/^/    /'
    case "$STUBS" in
        *"/ubus"*|*"/ubusd"*|*"/procd"*|*"/netifd"*|*"/dnsmasq"*|*"/rpcd"*|*"/uhttpd"*|*"/opkg"*|*"/libc.so"*|*"/libubox"*|*"/libblobmsg"*)
            echo "[x] Повреждены системные компоненты — установка невозможна. Нужна перепрошивка."
            exit 1
            ;;
    esac
    repair_stub_pkgs
    STUBS=$(scan_stubs | grep -vE '/(sing-box|forkop|xray|nfqws)$')
    if [ -n "$STUBS" ]; then
        echo "[x] Заглушки остались:"
        echo "$STUBS" | sed 's/^/    /'
        echo "[x] Остановка: система повреждена, требуется перепрошивка."
        exit 1
    fi
    echo "[+] Пакеты восстановлены."
else
    echo "[+] Заглушек не найдено."
fi
if ! verify_critical; then
    echo "[x] Критичные бинарники повреждены — остановка."
    exit 1
fi
echo "[+] Целостность критичных файлов в порядке."

# ==================================================
# ЭТАП 1: ПРОВЕРКА "ЖЕЛЕЗА" (ОБЩИЕ РЕСУРСЫ)
# ==================================================
echo "[-] Проверка базовых характеристик роутера..."

if [ ! -f /etc/openwrt_release ]; then
    echo "[x] ОШИБКА: Это не OpenWrt. Установка невозможна."
    exit 1
fi
. /etc/openwrt_release
RELEASE_MAJOR=$(echo "$DISTRIB_RELEASE" | cut -d. -f1)
RELEASE_MINOR=$(echo "$DISTRIB_RELEASE" | cut -d. -f2)

if [ "$RELEASE_MAJOR" -lt 24 ] || { [ "$RELEASE_MAJOR" -eq 24 ] && [ "$RELEASE_MINOR" -lt 10 ]; }; then
    echo "[x] ОШИБКА: Требуется OpenWrt 24.10 или новее. У вас версия $DISTRIB_RELEASE."
    exit 1
fi
echo " -> Версия OpenWrt: $DISTRIB_RELEASE (OK)"

ARCH=$(opkg print-architecture | awk '$1=="arch" && $2!="all" && $2!="noarch" {print $2; exit}')
SUPPORTED_ARCH="aarch64_cortex-a53 aarch64_cortex-a72 aarch64_generic mips_24kc mipsel_24kc arm_cortex-a7 arm_cortex-a9 x86_64 i386"
ARCH_OK=0
for a in $SUPPORTED_ARCH; do
    case "$ARCH" in *"$a"*) ARCH_OK=1; break ;; esac
done
if [ "$ARCH_OK" -eq 0 ]; then
    echo "[x] ОШИБКА: Архитектура $ARCH не поддерживается."
    exit 1
fi
echo " -> Архитектура: $ARCH (OK)"

TOTAL_RAM_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
if [ "$TOTAL_RAM_KB" -lt 65536 ]; then
    echo "[x] ОШИБКА: Слишком мало оперативной памяти (меньше 64 МБ)."
    exit 1
fi
echo " -> Общий объем RAM: $((TOTAL_RAM_KB / 1024)) МБ (OK)"

TOTAL_FLASH_KB=$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $2}' || df -k / | awk 'NR==2 {print $2}')
if [ "$TOTAL_FLASH_KB" -lt 16384 ]; then
    echo "[x] ОШИБКА: Слишком маленький размер флеш-памяти (меньше 16 МБ)."
    exit 1
fi
echo " -> Общий объем Flash: $((TOTAL_FLASH_KB / 1024)) МБ (OK)"
echo "[+] Базовые требования выполнены."

# ==================================================
# ЭТАП 2: ПОЛНАЯ ЗАЧИСТКА СИСТЕМЫ (forkop, sing-box, zapret, podkop, расширение)
# ==================================================
echo "[-] Принудительная остановка процессов..."
killall -9 forkop sing-box xray nfqws 2>/dev/null
sleep 1

echo "[-] Удаление симлинков автозапуска..."
rm -f /etc/rc.d/S*forkop /etc/rc.d/K*forkop 2>/dev/null
rm -f /etc/rc.d/S*sing-box /etc/rc.d/K*sing-box 2>/dev/null
rm -f /etc/rc.d/S*zapret /etc/rc.d/K*zapret 2>/dev/null
rm -f /etc/rc.d/S*podkop /etc/rc.d/K*podkop 2>/dev/null

echo "[-] Удаление старых пакетов..."
opkg remove --force-depends forkop luci-app-forkop luci-i18n-forkop-ru sing-box-forkop 2>/dev/null
opkg remove --force-depends sing-box sing-box-tiny sing-box-extended 2>/dev/null
opkg remove --force-depends podkop luci-app-podkop xray-core 2>/dev/null
opkg remove --force-depends zapret zapret2 2>/dev/null

echo "[-] Удаление расширения forkop-zapret (если установлено)..."
rm -rf /usr/libexec/forkop-zapret /usr/libexec/rpcd/forkop.zapret
rm -rf /www/luci-static/resources/view/forkop-zapret
rm -f /usr/share/luci/menu.d/luci-app-forkop-zapret.json
rm -f /usr/share/rpcd/acl.d/luci-app-forkop-zapret.json
rm -f /etc/config/forkop_zapret /etc/config/forkop_zapret.* /etc/forkop_zapret.conf

echo "[-] Очистка конфигураций..."
rm -rf /etc/config/forkop /etc/config/forkop.* /etc/forkop /usr/share/sing-box-forkop /etc/init.d/forkop /usr/bin/forkop
rm -rf /etc/config/sing-box /etc/sing-box /etc/init.d/sing-box /usr/bin/sing-box
rm -rf /opt/zapret /etc/zapret /etc/config/zapret /etc/init.d/zapret
rm -rf /etc/config/podkop /etc/podkop
echo "[+] Система очищена."

# ==================================================
# ЭТАП 3: ПРОВЕРКА СВОБОДНЫХ РЕСУРСОВ (ПОСЛЕ ЧИСТКИ)
# ==================================================
echo "[-] Проверка свободных ресурсов после очистки..."

FREE_FLASH_KB=$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $4}' || df -k / | awk 'NR==2 {print $4}')
if [ "$FREE_FLASH_KB" -lt 15360 ]; then
    echo "[x] ОШИБКА: Недостаточно свободного места для установки."
    echo "    Требуется: 15 МБ. Доступно: $((FREE_FLASH_KB / 1024)) МБ."
    exit 1
fi
echo " -> Свободно на Flash: $((FREE_FLASH_KB / 1024)) МБ (OK)"

FREE_RAM_KB=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
if [ "$FREE_RAM_KB" -lt 32768 ]; then
    echo "[!] ВНИМАНИЕ: Мало свободной оперативной памяти ($((FREE_RAM_KB / 1024)) МБ)."
    echo "    Рекомендуется перезагрузить роутер перед запуском Forkop."
fi

# ==================================================
# ЭТАП 4: УСТАНОВКА
# ==================================================
echo "[-] Исправление конфигурации opkg..."
cp /etc/opkg.conf /etc/opkg.conf.bak 2>/dev/null

cat <<EOF > /etc/opkg.conf
dest root /
dest ram /tmp
lists_dir ext /var/opkg-lists
option overlay_root /overlay
option check_signature
arch all 100
arch $ARCH 10
EOF

# Форсируем IPv4 на время скачиваний (иначе opkg/wget висят на IPv6)
trap 'enable_ipv6' EXIT INT TERM
disable_ipv6
echo "[-] IPv6 временно отключён (для скачиваний по IPv4)."

echo "[-] Обновление списков пакетов..."
opkg update

echo "[-] Установка зависимостей..."
opkg install luci-compat
opkg install luci-i18n-base-ru luci-i18n-ttyd-ru
opkg install libc ca-bundle kmod-inet-diag kmod-netlink-diag kmod-tun curl ucode ucode-mod-fs ucode-mod-uci kmod-nft-tproxy coreutils-base64 bind-dig nftables kmod-nft-nat kmod-nft-queue ip-full jsonfilter kmod-veth

echo "[-] Проверка, что зависимости установились настоящими файлами..."
if ! verify_critical; then
    echo "[!] Не все критичные пакеты установились. Пробую восстановить..."
    for pkg in ip-full curl bind-dig jsonfilter nftables; do
        opkg install --force-reinstall "$pkg" 2>/dev/null
    done
    if ! verify_critical; then
        echo "[x] Пакеты повреждены — установка остановлена. Нужна перепрошивка."
        exit 1
    fi
fi

echo "[-] Скачивание пакетов Forkop 1.0.5..."
BASE_URL="https://github.com/ushan0v/forkop/releases/download/1.0.5"
download "$BASE_URL/forkop_1.0.5.ipk" /tmp/forkop.ipk "Пакет forkop" || exit 1
download "$BASE_URL/luci-app-forkop_1.0.5.ipk" /tmp/luci-app-forkop.ipk "Пакет luci-app-forkop" || exit 1
download "$BASE_URL/luci-i18n-forkop-ru_1.0.5.ipk" /tmp/luci-i18n-forkop-ru.ipk "Пакет luci-i18n-forkop-ru" || exit 1
for f in /tmp/forkop.ipk /tmp/luci-app-forkop.ipk /tmp/luci-i18n-forkop-ru.ipk; do
    if ! tar -tzf "$f" >/dev/null 2>&1; then
        echo "[x] $f повреждён (не ipk/tar.gz)"
        exit 1
    fi
done
echo "[+] Пакеты Forkop скачаны и проверены."

echo "[-] Установка Forkop..."
opkg install --force-depends --force-overwrite /tmp/forkop.ipk /tmp/luci-app-forkop.ipk /tmp/luci-i18n-forkop-ru.ipk

# ==================================================
# ЭТАП 5: ZAPRET, FAKE-ФАЙЛЫ И КОНФИГ
# ==================================================
if [ ! -f /etc/init.d/forkop ]; then
    echo "[x] ОШИБКА: Установка Forkop не удалась."
    exit 1
fi
echo "[+] Forkop успешно установлен."

# 5.1 — sing-box через штатный component_action Forkop (как кнопка в LuCI)
# Всегда ставим полный extended (не compressed).
if ask_yes_d "Установить sing-box (extended) через Forkop?"; then
    SINGBOX_ACTION="install_extended"
    FREE_KB=$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt 120000 ]; then
        echo "[!] Внимание: свободно $((FREE_KB / 1024)) МБ на flash."
        echo "    Полный extended (~100 МБ) может не поместиться — установка может упасть по месту."
    fi
    if ! forkop_component sing_box "$SINGBOX_ACTION" "Установка sing-box (extended, Forkop)"; then
        echo "[!] sing-box не установился. Проверьте: logread -e forkop / forkop get_sing_box_status"
    fi
else
    echo "[i] sing-box не устанавливается (по желанию пользователя)."
fi

# 5.2 — zapret через Forkop, с ДОПОЛНИТЕЛЬНЫМ подтверждением
if ask_yes_d "Установить Zapret (DPI-обход) через Forkop?"; then
    if ask_yes "Подтвердить установку компонента Zapret через Forkop?"; then
        if ! forkop_component zapret install "Установка компонента Zapret (Forkop)"; then
            echo "[!] Zapret не установился. Проверьте: logread -e forkop / forkop get_zapret_status"
        fi
    else
        echo "[i] Установка Zapret отменена."
    fi
else
    echo "[i] Zapret не устанавливается."
fi

echo "[-] Скачивание fake-файлов для zapret..."
mkdir -p /opt/zapret/files/fake
BASE="https://github.com/Flowseal/zapret-discord-youtube/raw/refs/heads/main/bin"
for f in stun.bin stun2.bin quic_initial_tencent_com.bin quic_initial_steamcommunity_com.bin tls_clienthello_sochi_park.bin quic_initial_4pda_to.bin quic_initial_5ka_ru.bin tls_clienthello_5ka_ru.bin quic_initial_rutube_ru.bin; do
  download "$BASE/$f" "/opt/zapret/files/fake/$f" "fake-файл $f" || echo " [!] пропущен: $f"
done

# 5.3 — авто-настройка из config/
if [ -d "$CONFIG_DIR" ] && [ -f "$CONFIG_DIR/forkop" ]; then
    if ask_yes_d "Применить сохранённую конфигурацию (forkop + локальные списки)?"; then
        echo "[-] Применение конфигурации из $CONFIG_DIR ..."
        mkdir -p /etc/forkop
        cp "$CONFIG_DIR/forkop" /etc/config/forkop
        [ -f "$CONFIG_DIR/forkop_zapret" ] && cp "$CONFIG_DIR/forkop_zapret" /etc/config/forkop_zapret
        [ -f "$CONFIG_DIR/forkop_zapret.conf" ] && cp "$CONFIG_DIR/forkop_zapret.conf" /etc/forkop_zapret.conf
        [ -f "$CONFIG_DIR/zapret" ] && cp "$CONFIG_DIR/zapret" /etc/config/zapret
        [ -f "$CONFIG_DIR/sing-box" ] && cp "$CONFIG_DIR/sing-box" /etc/config/sing-box
        [ -f "$CONFIG_DIR/forkop_rules_rus.json" ] && cp "$CONFIG_DIR/forkop_rules_rus.json" /etc/forkop/forkop_rules_rus.json
        [ -f "$CONFIG_DIR/forkop_rules_ai.json" ] && cp "$CONFIG_DIR/forkop_rules_ai.json" /etc/forkop/forkop_rules_ai.json
        for f in "$CONFIG_DIR"/*.srs; do
            [ -f "$f" ] && cp "$f" /etc/forkop/
        done
        uci commit forkop 2>/dev/null
        uci commit forkop_zapret 2>/dev/null
        uci commit zapret 2>/dev/null
        uci commit sing-box 2>/dev/null
        echo "[+] Конфигурация применена."
        NEED_VPN_KEY=1
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
else
    echo "[i] Каталог config/ не найден — авто-настройка пропущена."
fi

# 5.4 — запуск с проверкой; автозапуск включаем только после успеха
if [ "$NEED_VPN_KEY" = "1" ]; then
    echo "[-] Автозапуск Forkop пока не включаю: сначала добавьте ключ/подписку в main_vpn."
    echo "    После добавления запустите: /etc/init.d/forkop start"
    /etc/init.d/forkop disable 2>/dev/null
else
    echo "[-] Запуск Forkop (автозапуск пока выключен)..."
    chmod +x /etc/init.d/forkop
    /etc/init.d/forkop disable 2>/dev/null
    /etc/init.d/forkop start
    sleep 8
    if ps 2>/dev/null | grep -v grep | grep -q 'sing-box run'; then
        /etc/init.d/forkop enable 2>/dev/null
        echo "[+] Forkop запущен, автозапуск включён."
    else
        echo "[!] Forkop не запустился — автозапуск НЕ включён."
        echo "    Проверьте: logread -e forkop"
    fi
fi

# ==================================================
# ЭТАП 6: ФИНАЛИЗАЦИЯ
# ==================================================
echo "[-] Возврат IPv6 и очистка кэша LuCI..."
enable_ipv6
trap - EXIT INT TERM

rm -rf /tmp/luci-*
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart

rm -f /tmp/forkop.ipk /tmp/luci-app-forkop.ipk /tmp/luci-i18n-forkop-ru.ipk

echo "=================================================="
echo "[+] ВСЁ ГОТОВО! Система настроена начисто."
echo "[i] Откройте LuCI в режиме Инкогнито (Ctrl+F5)."
echo "=================================================="
