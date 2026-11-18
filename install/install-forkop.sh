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
DID_INSTALL_SINGBOX=0
DID_INSTALL_ZAPRET=0
DID_INSTALL_ADDON=0
rm -f /tmp/forkop-zapret-install-addon
CLEAN_ONLY=0
SKIP_CLEAN="${FZ_SKIP_CLEAN:-0}"
case "${1:-}" in
    --clean-only|clean) CLEAN_ONLY=1 ;;
esac

ASK_SEP="------------------------------------------------------------"

ask_yes() {
    [ "$ASSUME_YES" = "1" ] && return 0
    echo ""
    echo "$ASK_SEP"
    echo "${2:-$1}"
    echo "$ASK_SEP"
    printf "%s(По умолчанию N)(y/n): " "$1"
    if [ -r /dev/tty ]; then
        read ans < /dev/tty
    else
        read ans
    fi
    case "$ans" in y|Y|yes|YES|да|Да) return 0 ;; *) return 1 ;; esac
}

ask_yes_d() {
    [ "$ASSUME_YES" = "1" ] && return 0
    echo ""
    echo "$ASK_SEP"
    echo "${2:-$1}"
    echo "$ASK_SEP"
    printf "%s(По умолчанию Y)(y/n): " "$1"
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

# --- Очистка остатков Zapret-Manager и проверка nftables/сети ---
cleanup_network_leftovers() {
    echo "[-] Удаление остатков Zapret-Manager и других надстроек..."
    for s in zapret zapret2 tg-ws-proxy-go tg-ws-proxy-rs zapret-manager; do
        [ -x "/etc/init.d/$s" ] && /etc/init.d/$s stop 2>/dev/null
        [ -x "/etc/init.d/$s" ] && /etc/init.d/$s disable 2>/dev/null
    done
    if [ -f /etc/zm-steer/owned ]; then
        for s in steer splify2; do
            [ -x "/etc/init.d/$s" ] && /etc/init.d/$s stop 2>/dev/null
            [ -x "/etc/init.d/$s" ] && /etc/init.d/$s disable 2>/dev/null
        done
        opkg remove --force-depends steer splify2 2>/dev/null
    fi
    rm -f /usr/bin/zms /usr/bin/zmsA /usr/bin/zmw
    rm -rf /opt/zapret2 /opt/zapret_backup /opt/zapret-manager-luci /opt/zapret-manager*
    rm -f /etc/config/zapret2 /etc/init.d/zapret2
    rm -f /usr/libexec/rpcd/zapret-manager /etc/zapret_manager_expert_mode
    opkg remove --force-depends luci-app-zapret-manager 2>/dev/null
    rm -rf /www/luci-static/resources/view/zapret-manager
    rm -f /usr/share/luci/menu.d/luci-app-zapret-manager.json /usr/share/rpcd/acl.d/luci-app-zapret-manager.json
    rm -rf /etc/tg-ws-proxy /tmp/zapret_temp /tmp/zapret-manager-luci /tmp/zm_luci_latest /tmp/PodkopAWG
    rm -f /usr/bin/tg-ws-proxy-go /usr/bin/tg-ws-proxy-rs /usr/bin/tg-ws-proxy-go_ver /usr/bin/tg-ws-proxy-rs_ver
    rm -f /etc/init.d/tg-ws-proxy-go /etc/init.d/tg-ws-proxy-rs /etc/byedpi_dns_localuse
    if [ -f /etc/zm-steer/owned ]; then
        rm -rf /etc/zm-steer /etc/steer* /etc/config/steer* /etc/config/splify2*
        rm -f /etc/init.d/steer /etc/init.d/splify2
    fi
    sed -i '/zapret-manager\|Zapret-Manager\|zmsA\|steer\|splify2\|tg-ws-proxy/d' /etc/crontabs/root 2>/dev/null
    sed -i '/zapret-manager\|Zapret-Manager\|zmsA\|steer\|splify2\|tg-ws-proxy/d' /etc/rc.local 2>/dev/null

    echo "[-] Проверка nftables и сетевых настроек..."
    for t in zapret zapret2 podkop forkop ForkopTable byedpi steer splify2 zmwarp v2ray xray v2raya; do
        for fam in inet ip ip6; do
            nft delete table "$fam" "$t" 2>/dev/null
        done
    done
    ip rule show 2>/dev/null | awk -F: '/lookup (forkop|podkop|zapret|zapret2|byedpi|steer|splify2|v2ray|xray)/ {print $1}' | while read -r prio; do
        [ -n "$prio" ] && ip rule del priority "$prio" 2>/dev/null
    done
    for tbl in 100 105 200 300; do
        ip route flush table "$tbl" 2>/dev/null
    done
    rm -f /etc/nftables.d/zapret.nft /etc/nftables.d/zapret2.nft /etc/nftables.d/podkop.nft /etc/nftables.d/byedpi.nft /etc/nftables.d/v2ray.nft /etc/nftables.d/xray.nft /etc/nftables.d/v2raya.nft 2>/dev/null

    if [ "$(uci -q get dhcp.@dnsmasq[0].server)" = "127.0.0.42" ]; then
        uci -q delete dhcp.@dnsmasq[0].server
    fi
    uci -q delete dhcp.@dnsmasq[0].podkop_noresolv
    uci -q delete dhcp.@dnsmasq[0].podkop_cachesize
    if [ "$(uci -q get dhcp.@dnsmasq[0].noresolv)" = "1" ]; then
        uci set dhcp.@dnsmasq[0].noresolv='0'
    fi
    uci commit dhcp 2>/dev/null

    if nft list ruleset >/dev/null 2>&1; then
        echo "[+] nftables читается"
    else
        echo "[!] nftables вернул ошибку — проверьте правила вручную"
    fi
    if command -v fw4 >/dev/null 2>&1; then
        if fw4 check >/dev/null 2>&1; then
            echo "[+] fw4 check: OK"
        else
            echo "[!] fw4 check: есть ошибки в firewall"
        fi
    fi
}

# --- Утилита расширения RAM за счёт ROM: swap-utils + swapfile 64 МБ ---
install_ram_expander() {
    echo "[-] Установка утилиты расширения RAM (swap-utils + swapfile 64 МБ)..."
    opkg install swap-utils 2>/dev/null || true
    if [ -f /swapfile ]; then
        echo "[i] swapfile уже существует — включаю."
        swapon /swapfile 2>/dev/null || true
        return 0
    fi
    FREE_KB=$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $4}')
    if [ "${FREE_KB:-0}" -lt 102400 ]; then
        echo "[!] Мало места для swapfile 64 МБ (нужно ~100 МБ свободно)."
        echo "    swap-utils установлен, swapfile не создан."
        return 1
    fi
    dd if=/dev/zero of=/swapfile bs=1M count=64 2>/dev/null || return 1
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1 || { rm -f /swapfile; return 1; }
    swapon /swapfile 2>/dev/null || return 1
    if [ -f /etc/rc.local ]; then
        grep -q '/swapfile' /etc/rc.local || sed -i '/^exit 0/i [ -f /swapfile ] \&\& swapon /swapfile 2>/dev/null' /etc/rc.local
    else
        echo '[ -f /swapfile ] && swapon /swapfile 2>/dev/null' > /etc/rc.local
        chmod +x /etc/rc.local
    fi
    echo "[+] swapfile 64 МБ создан и включён."
    return 0
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
if [ "$SKIP_CLEAN" = "1" ]; then
    echo "[i] Очистка уже выполнена — пропускаю Этап 2."
else
echo "[-] Очистка временных файлов предыдущей установки..."
rm -f /tmp/forkop.ipk /tmp/luci-app-forkop.ipk /tmp/luci-i18n-forkop-ru.ipk
rm -f /tmp/forkop-zapret-install-addon /tmp/forkop-zapret-need-key
rm -rf /tmp/sing-box-extended-x86 /tmp/sing-box-extended
rm -rf /tmp/forkop_zapret
rm -f /tmp/forkop-zapret-install/repo.tar.gz

echo "[-] Принудительная остановка процессов..."
killall -9 forkop sing-box xray nfqws zapret zapret2 nfqws2 tg-ws-proxy-go tg-ws-proxy-rs 2>/dev/null
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

echo "[-] Удаление остатков sing-box (EikeiDev extended и др.)..."
rm -rf /usr/libexec/sing-box-core /usr/libexec/sing-box /usr/bin/sing-box
rm -rf /opt/sing-box /usr/share/sing-box /usr/lib/sing-box
rm -rf /root/sing-box-install /tmp/sing-box-install /tmp/sing-box-install.*
rm -f /etc/sing-box-version.cache /usr/bin/.sing-box.tmp.*
rm -f /etc/forkop/sing-box-variant /etc/forkop/sing-box-version
rm -rf /etc/forkop/backup /etc/forkop/backup-* /etc/forkop/*.backup
rm -rf /tmp/forkop-sing-box* /tmp/sing-box-backup*
opkg clean 2>/dev/null

echo "[-] Удаление остатков v2ray/xray..."
opkg remove --force-depends v2ray-core xray-core v2raya luci-app-v2raya 2>/dev/null
rm -rf /etc/v2ray /usr/bin/v2ray /usr/share/v2ray /etc/config/v2ray /etc/init.d/v2ray
rm -rf /etc/xray /usr/bin/xray /usr/share/xray /etc/config/xray /etc/init.d/xray
rm -rf /etc/v2raya /usr/bin/v2raya /etc/config/v2raya /etc/init.d/v2raya
rm -f /etc/nftables.d/v2ray.nft /etc/nftables.d/xray.nft /etc/nftables.d/v2raya.nft

cleanup_network_leftovers
echo "[+] Система очищена."
fi

if [ "$CLEAN_ONLY" = "1" ]; then
    FREE_FLASH_KB=$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $4}' || df -k / | awk 'NR==2 {print $4}')
    echo "[+] Очистка завершена. Свободно на Flash: $(( ${FREE_FLASH_KB:-0} / 1024 )) МБ."
    exit 0
fi

# ==================================================
# ЭТАП 3: ПРОВЕРКА СВОБОДНЫХ РЕСУРСОВ (ПОСЛЕ ЧИСТКИ)
# ==================================================
echo "[-] Проверка свободных ресурсов после очистки..."

FREE_FLASH_KB=$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $4}' || df -k / | awk 'NR==2 {print $4}')
if [ "${FREE_FLASH_KB:-0}" -lt 10240 ]; then
    echo "[x] ОШИБКА: Недостаточно свободного места для установки."
    echo "    Требуется: 10 МБ. Доступно: $(( ${FREE_FLASH_KB:-0} / 1024 )) МБ."
    exit 1
fi
echo " -> Свободно на Flash: $(( ${FREE_FLASH_KB:-0} / 1024 )) МБ (OK)"

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
opkg install libc ca-bundle kmod-inet-diag kmod-netlink-diag kmod-tun curl libcurl4 ucode ucode-mod-fs ucode-mod-uci kmod-nft-tproxy coreutils-base64 bind-dig bind-libs nftables kmod-nft-nat kmod-nft-queue ip-full jsonfilter kmod-veth
cleanup_network_leftovers

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

# 5.1 — выбор версии sing-box (только через Forkop); без успеха не продолжаем
SB_INSTALLED=0
SB_SKIPPED=0
while [ "$SB_INSTALLED" = "0" ] && [ "$SB_SKIPPED" = "0" ]; do
    SB_ACTION=""
    if [ "$ASSUME_YES" = "1" ]; then
        SB_ACTION="install_extended"
        echo "[i] ASSUME_YES: выбран sing-box extended."
    else
        echo ""
        echo "$ASK_SEP"
        echo "Выберите версию sing-box (установка через Forkop):"
        echo "  1) tiny"
        echo "  2) stable"
        echo "  3) extended"
        echo "  4) extended compressed"
        echo "  0) не устанавливать"
        echo "$ASK_SEP"
        printf "Версия (1/2/3/4/0, по умолчанию 3 extended): "
        if [ -r /dev/tty ]; then
            read -r sb_choice < /dev/tty
        else
            read -r sb_choice
        fi
        case "$sb_choice" in
            0) SB_ACTION="" ;;
            1) SB_ACTION="install_tiny" ;;
            2) SB_ACTION="install_stable" ;;
            3|"") SB_ACTION="install_extended" ;;
            4) SB_ACTION="install_extended_compressed" ;;
            *) echo "[!] Неверный выбор — используется extended."; SB_ACTION="install_extended" ;;
        esac
    fi
    if [ -z "$SB_ACTION" ]; then
        SB_SKIPPED=1
        echo "[i] sing-box не устанавливается (явный отказ)."
        break
    fi
    if [ "$SB_ACTION" = "install_extended" ]; then
        FREE_KB=$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $4}')
        if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt 120000 ]; then
            echo "[!] Внимание: свободно $((FREE_KB / 1024)) МБ на flash."
            echo "    Полный extended (~100 МБ) может не поместиться — установка может упасть по месту."
        fi
    fi
    if forkop_component sing_box "$SB_ACTION" "Установка sing-box ($SB_ACTION, Forkop)"; then
        SB_INSTALLED=1
        DID_INSTALL_SINGBOX=1
        if [ "$SB_ACTION" = "install_extended_compressed" ]; then
            install_ram_expander || echo "[!] Утилита расширения RAM не настроена."
        fi
    else
        echo "[!] sing-box не установился."
        echo "[i] Если мало места: rm -rf /usr/libexec/sing-box-core /root/sing-box-install /tmp/sing-box-install; opkg clean"
        if [ "$ASSUME_YES" = "1" ]; then
            echo "[x] Установка sing-box не удалась — остановка (ASSUME_YES)."
            exit 1
        fi
        echo "[i] Попробуйте другую версию или выберите 0 (не устанавливать)."
    fi
done

# 5.2 — zapret через Forkop, затем (только при успехе) аддон zapret+forkop
if ask_yes_d "Установить Zapret (DPI-обход) через Forkop?" "Будет установлен компонент Zapret через Forkop: nfqws, правила nftables и fake-файлы."; then
    if ask_yes_d "Подтвердить установку компонента Zapret через Forkop?" "Повторное подтверждение: Zapret будет установлен и включён в Forkop."; then
        if forkop_component zapret install "Установка компонента Zapret (Forkop)"; then
            DID_INSTALL_ZAPRET=1
            if ask_yes_d "Установить аддон zapret+forkop?" "Аддон zapret+forkop помогает подбирать стратегии для zapret: автоподбор по секциям, проверка доменов и ручной конструктор."; then
                DID_INSTALL_ADDON=1
            else
                echo "[i] Аддон zapret+forkop не устанавливается."
            fi
        else
            echo "[!] Zapret не установился. Проверьте: logread -e forkop / forkop get_zapret_status"
        fi
    else
        echo "[i] Установка Zapret отменена."
    fi
else
    echo "[i] Zapret не устанавливается."
fi

if [ "$DID_INSTALL_ZAPRET" = "1" ]; then
    echo "[-] Скачивание fake-файлов для zapret (в /tmp)..."
    FAKE_TMP="/tmp/zapret-fake"
    rm -rf "$FAKE_TMP"
    mkdir -p "$FAKE_TMP"
    BASE="https://github.com/Flowseal/zapret-discord-youtube/raw/refs/heads/main/bin"
    for f in stun.bin stun2.bin quic_initial_tencent_com.bin quic_initial_steamcommunity_com.bin tls_clienthello_sochi_park.bin quic_initial_4pda_to.bin quic_initial_5ka_ru.bin tls_clienthello_5ka_ru.bin quic_initial_rutube_ru.bin; do
      download "$BASE/$f" "$FAKE_TMP/$f" "fake-файл $f" || echo " [!] пропущен: $f"
    done
    mkdir -p /opt/zapret/files/fake
    cp -f "$FAKE_TMP"/* /opt/zapret/files/fake/ 2>/dev/null
    rm -rf "$FAKE_TMP"
fi

# 5.3 — авто-настройка из config/ (только если что-то установлено)
if [ -d "$CONFIG_DIR" ] && [ -f "$CONFIG_DIR/forkop" ]; then
    if [ "$DID_INSTALL_SINGBOX" = "1" ] && [ "$DID_INSTALL_ZAPRET" = "1" ] && [ "$DID_INSTALL_ADDON" = "1" ]; then
        if ask_yes_d "Применить сохранённую конфигурацию (forkop + локальные списки)?" "Будут скопированы конфиг forkop, локальные наборы правил (включая forkop_rules_ai.json) и настройки расширения."; then
            echo "[-] Применение конфигурации из $CONFIG_DIR ..."
            mkdir -p /etc/forkop
            cp "$CONFIG_DIR/forkop" /etc/config/forkop
            if [ "$DID_INSTALL_ADDON" = "1" ]; then
                [ -f "$CONFIG_DIR/forkop_zapret" ] && cp "$CONFIG_DIR/forkop_zapret" /etc/config/forkop_zapret
                [ -f "$CONFIG_DIR/forkop_zapret.conf" ] && cp "$CONFIG_DIR/forkop_zapret.conf" /etc/forkop_zapret.conf
            fi
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
        fi
    else
        echo "[i] Не всё установлено (нужны sing-box + zapret + аддон) — конфигурация не запрашивается."
    fi
else
    echo "[i] Каталог config/ не найден — авто-настройка пропущена."
fi

# 5.4 — запуск с проверкой; автозапуск включаем только после успеха
if [ "$NEED_VPN_KEY" = "1" ]; then
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

if [ "$FZ_WRAPPER" = "1" ]; then
    if [ "$DID_INSTALL_ADDON" = "1" ]; then
        touch /tmp/forkop-zapret-install-addon
    fi
    if [ "$NEED_VPN_KEY" = "1" ]; then
        touch /tmp/forkop-zapret-need-key
    fi
else
    if [ "$NEED_VPN_KEY" = "1" ]; then
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
fi
