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

echo "[-] Обновление списков пакетов..."
opkg update

echo "[-] Установка зависимостей..."
opkg install luci-compat
opkg install luci-i18n-base-ru luci-i18n-ttyd-ru
opkg install libc ca-bundle kmod-inet-diag kmod-netlink-diag kmod-tun curl ucode ucode-mod-fs ucode-mod-uci kmod-nft-tproxy coreutils-base64 bind-dig nftables kmod-nft-nat kmod-nft-queue ip-full jsonfilter kmod-veth sing-box

echo "[-] Скачивание пакетов Forkop 1.0.5..."
cd /tmp
BASE_URL="https://github.com/ushan0v/forkop/releases/download/1.0.5"
wget -q --no-check-certificate -O forkop.ipk "$BASE_URL/forkop_1.0.5.ipk"
wget -q --no-check-certificate -O luci-app-forkop.ipk "$BASE_URL/luci-app-forkop_1.0.5.ipk"
wget -q --no-check-certificate -O luci-i18n-forkop-ru.ipk "$BASE_URL/luci-i18n-forkop-ru_1.0.5.ipk"

echo "[-] Установка Forkop..."
opkg install --force-depends --force-overwrite /tmp/forkop.ipk /tmp/luci-app-forkop.ipk /tmp/luci-i18n-forkop-ru.ipk

# ==================================================
# ЭТАП 5: ZAPRET, FAKE-ФАЙЛЫ И ЗАПУСК
# ==================================================
if [ ! -f /etc/init.d/forkop ]; then
    echo "[x] ОШИБКА: Установка Forkop не удалась."
    exit 1
fi
echo "[+] Forkop успешно установлен."

# 5.1 — extended sing-box
if ask_yes_d "Установить extended sing-box?"; then
    case "$ARCH" in
        x86_64|i386)
            echo "[i] x86: запускаю scripts/install-sing-box-extended-x86.sh"
            if [ -f "$REPO_DIR/scripts/install-sing-box-extended-x86.sh" ]; then
                sh "$REPO_DIR/scripts/install-sing-box-extended-x86.sh" || echo "[!] Не удалось; выполните скрипт вручную."
            else
                echo "[i] Скрипт не найден рядом. Скачайте его из репозитория и выполните вручную."
            fi
            ;;
        *)
            echo "[-] Установка sing-box-extended из фидов OpenWrt..."
            opkg install --force-overwrite sing-box-extended 2>/dev/null || echo "[!] Не удалось; установите sing-box-extended вручную."
            ;;
    esac
fi

# 5.2 — zapret
if ask_yes_d "Установить zapret (DPI-обход)?"; then
    echo "[-] Установка zapret из фидов..."
    opkg install zapret 2>/dev/null || echo "[!] Не удалось установить zapret; установите вручную."
fi

echo "[-] Скачивание fake-файлов для zapret..."
mkdir -p /opt/zapret/files/fake
BASE="https://github.com/Flowseal/zapret-discord-youtube/raw/refs/heads/main/bin"
for f in stun.bin stun2.bin quic_initial_tencent_com.bin quic_initial_steamcommunity_com.bin tls_clienthello_sochi_park.bin quic_initial_4pda_to.bin quic_initial_5ka_ru.bin tls_clienthello_5ka_ru.bin quic_initial_rutube_ru.bin; do
  echo " -> Скачиваем $f"
  wget -q -U "Mozilla/5.0" -O "/opt/zapret/files/fake/$f" "$BASE/$f" || echo " [!] Не удалось скачать: $f"
done

echo "[-] Включение и запуск Forkop..."
chmod +x /etc/init.d/forkop
/etc/init.d/forkop enable
/etc/init.d/forkop start

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
        for f in "$CONFIG_DIR"/*.srs; do
            [ -f "$f" ] && cp "$f" /etc/forkop/
        done
        uci commit forkop 2>/dev/null
        uci commit forkop_zapret 2>/dev/null
        uci commit zapret 2>/dev/null
        uci commit sing-box 2>/dev/null
        /etc/init.d/forkop reload 2>/dev/null || /etc/init.d/forkop restart 2>/dev/null
        echo "[+] Конфигурация применена."
        echo "[i] VPN-подписка/ключи в конфиг НЕ входят — добавьте их в LuCI (Forkop → Connections)."
    fi
else
    echo "[i] Каталог config/ не найден — авто-настройка пропущена."
fi

# ==================================================
# ЭТАП 6: ФИНАЛИЗАЦИЯ
# ==================================================
echo "[-] Очистка кэша LuCI..."
rm -rf /tmp/luci-*
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart

rm -f /tmp/forkop.ipk /tmp/luci-app-forkop.ipk /tmp/luci-i18n-forkop-ru.ipk

echo "=================================================="
echo "[+] ВСЁ ГОТОВО! Система настроена начисто."
echo "[i] Откройте LuCI в режиме Инкогнито (Ctrl+F5)."
echo "=================================================="
