#!/bin/sh
# Файл: /usr/libexec/forkop-zapret/runner.sh

if [ -f "$LOCK_FILE" ] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
    echo "runner.sh уже запущен (PID $(cat "$LOCK_FILE")). Выходим."
    exit 0
fi

PARSER="/usr/libexec/forkop-zapret/parser.sh"
WORK_DIR="/tmp/forkop_zapret"
LOG_FILE="$WORK_DIR/live.log"
LOCK_FILE="$WORK_DIR/runner.lock"
STOP_FLAG="$WORK_DIR/stop.flag"
STR_FILE="$WORK_DIR/strategies.txt"
RESULTS_FILE="$WORK_DIR/results.txt"
IP_CACHE_FILE="$WORK_DIR/resolved_ips.txt"

CAT_GENERAL="$WORK_DIR/cat_general.txt"
CAT_FAKETLS="$WORK_DIR/cat_faketls.txt"
CAT_YOUTUBE="$WORK_DIR/cat_youtube.txt"
CAT_DISCORD="$WORK_DIR/cat_discord.txt"
CAT_GV="$WORK_DIR/cat_gv.txt"

SANDBOX_QNUM=290
SANDBOX_MARK="0x29a"
SANDBOX_TABLE="zapret_test_sandbox"

NFQWS_BIN="/opt/zapret/nfq/nfqws"
[ ! -x "$NFQWS_BIN" ] && NFQWS_BIN=$(command -v nfqws 2>/dev/null)

GH_MAIN="https://github.com"
GH_RAW="https://raw.githubusercontent.com"
STR_YT_URL="${GH_RAW}/StressOzz/Zapret-Manager/refs/heads/main/files/StrYoutube"

PORTS_UDP="88,1024-2407,2409-4499,4502-19293,19345-49999,50101-65535"
PORTS_TCP="2802,2302,2502,3478-3480,3724,6000-8000,8085,8090,8100,8903,8904,25565,27015-27030,27036-27037,35500-35600,50001,60442"
PARALLEL_CURL=6

short_strategy_name() {
    case "$1" in
        General_v*) echo "G$(echo "${1#General_v}" | sed 's/_.*//')" ;;
        FakeTLS_SNIExt_679) echo "FT1" ;;
        FakeTLS_Multidisorder_MidSLD) echo "FT2" ;;
        FakeTLS_HostFake_AltOrder) echo "FT3" ;;
        FakeTLS_Google_MD5) echo "FT4" ;;
        FakeTLS_Multisplit_Badseq1000) echo "FT5" ;;
        FakeTLS_FakedSplit_Badseq2) echo "FT6" ;;
        FakeTLS_Multisplit_Badseq10M) echo "FT7" ;;
        FakeTLS_Pattern00_MD5) echo "FT8" ;;
        FakeTLS_*) echo "FT" ;;
        Discord_Dv) echo "D0" ;;
        Discord_Dv*) echo "D$(echo "${1#Discord_Dv}" | sed 's/_.*//')" ;;
        YouTube_Yv*) echo "YT$(echo "${1#YouTube_Yv}" | sed 's/^0*//' | sed 's/_.*//')" ;;
        Game_Gv*) echo "GV$(echo "${1#Game_Gv}" | sed 's/_.*//')" ;;
        *) echo "$1" ;;
    esac
}

# Скоростные пороги curl (единые константы — легко тюнить)
SPEED_LIMIT_PAGE=3000
SPEED_TIME_PAGE=2
SPEED_LIMIT_JS=5000
SPEED_TIME_JS=2

mkdir -p "$WORK_DIR"

kill_pid_tree() {
    local pid="$1"
    [ -z "$pid" ] && return 0
    local children=$(ps -o pid,ppid 2>/dev/null | awk -v p="$pid" '$2 == p {print $1}')
    if [ -z "$children" ] && [ -f "/proc/$pid/task/$pid/children" ]; then
        children=$(cat "/proc/$pid/task/$pid/children" 2>/dev/null)
    fi
    for child in $children; do
        kill_pid_tree "$child"
    done
    kill -9 "$pid" 2>/dev/null
}

# Переносимый аналог `pkill -f` (в busybox applet pkill отсутствует).
kill_matching() {
    local pat="$1"
    ps 2>/dev/null | grep -E "$pat" | grep -v grep | awk '{print $1}' | while read -r p; do
        [ -n "$p" ] && kill -9 "$p" 2>/dev/null
    done
}

load_settings() {
    local run_sec="$1"
    WAN_DEV=$(ip -4 route show default table main 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
    if [ -z "$WAN_DEV" ]; then
        WAN_DEV=$(uci -q get network.wan.device || uci -q get network.wan.ifname)
    fi

    CONF_FILE="/etc/forkop_zapret.conf"
    local fz_cfg=0
    if [ -n "$run_sec" ]; then
        local _us=$(echo "$run_sec" | tr ',' '_' | tr -c 'a-zA-Z0-9_' '_' | sed 's/^_*//; s/_*$//')
        if uci -q show "forkop_zapret.cfg_${_us}" 2>/dev/null | grep -q .; then
            fz_cfg=1
            DNS_PROTO=$(uci -q get "forkop_zapret.cfg_${_us}.dns_proto" 2>/dev/null)
            DNS_SERVER=$(uci -q get "forkop_zapret.cfg_${_us}.dns_server" 2>/dev/null)
            DNS_SERVERS="$DNS_SERVER"
            STRAT_CATS=$(uci -q get "forkop_zapret.cfg_${_us}.strat_cats" 2>/dev/null)
            ALL_COMBOS=$(uci -q get "forkop_zapret.cfg_${_us}.all_combos" 2>/dev/null)
            AUTO_APPLY=$(uci -q get "forkop_zapret.cfg_${_us}.auto_apply" 2>/dev/null)
            VPN_SECTION=$(uci -q get "forkop_zapret.cfg_${_us}.vpn_section" 2>/dev/null)
            ONLY_STRAT_UPDATE=$(uci -q get "forkop_zapret.cfg_${_us}.only_strat_update" 2>/dev/null)
            DISABLE_UPDATES=$(uci -q get "forkop_zapret.cfg_${_us}.disable_updates" 2>/dev/null)
            INCLUDE_ZM_DOMAINS=$(uci -q get "forkop_zapret.cfg_${_us}.include_zm_domains" 2>/dev/null)
            CUSTOM_STRATEGY=$(uci -q get "forkop_zapret.cfg_${_us}.custom_strategy" 2>/dev/null)
            FOLLOW_ENABLED=$(uci -q get "forkop_zapret.cfg_${_us}.follow_enabled" 2>/dev/null)
            FOLLOW_FROM=$(uci -q get "forkop_zapret.cfg_${_us}.follow_from" 2>/dev/null)
        fi
    fi

    if [ "$fz_cfg" = "0" ]; then
        [ -f "$CONF_FILE" ] && . "$CONF_FILE" 2>/dev/null

        # uci-fallback: если в plain-конфиге переменной нет — читаем из uci
        [ -z "$DNS_PROTO" ]          && DNS_PROTO=$(uci -q get forkop_zapret.settings.dns_proto 2>/dev/null)
        [ -z "$DNS_SERVER" ]         && DNS_SERVER=$(uci -q get forkop_zapret.settings.dns_server 2>/dev/null)
        [ -z "$STRAT_CATS" ]         && STRAT_CATS=$(uci -q get forkop_zapret.settings.strat_cats 2>/dev/null)
        [ -z "$ALL_COMBOS" ]         && ALL_COMBOS=$(uci -q get forkop_zapret.settings.all_combos 2>/dev/null)
        [ -z "$VPN_SECTION" ]        && VPN_SECTION=$(uci -q get forkop_zapret.settings.vpn_section 2>/dev/null)
        [ -z "$ONLY_STRAT_UPDATE" ]  && ONLY_STRAT_UPDATE=$(uci -q get forkop_zapret.settings.only_strat_update 2>/dev/null)
        [ -z "$DISABLE_UPDATES" ]    && DISABLE_UPDATES=$(uci -q get forkop_zapret.settings.disable_updates 2>/dev/null)
        [ -z "$INCLUDE_ZM_DOMAINS" ] && INCLUDE_ZM_DOMAINS=$(uci -q get forkop_zapret.settings.include_zm_domains 2>/dev/null)
        [ -z "$CUSTOM_STRATEGY" ]    && CUSTOM_STRATEGY=$(uci -q get forkop_zapret.settings.custom_strategy 2>/dev/null)
    fi

    # Явные параметры запуска из UI имеют приоритет над сохранённым конфигом
    [ -n "${FZ_STRAT_CATS:-}" ]  && STRAT_CATS="$FZ_STRAT_CATS"
    [ -n "${FZ_ALL_COMBOS:-}" ]  && ALL_COMBOS="$FZ_ALL_COMBOS"
    [ -n "${FZ_INCLUDE_ZM:-}" ]  && INCLUDE_ZM_DOMAINS="$FZ_INCLUDE_ZM"

    [ -z "$DNS_PROTO" ]          && DNS_PROTO="doh"
    [ -z "$DNS_SERVER" ]         && DNS_SERVER="1.1.1.1"
    [ -z "$DNS_SERVERS" ]        && DNS_SERVERS="${DNS_PROTO}|${DNS_SERVER}"
    [ -z "$STRAT_CATS" ]         && STRAT_CATS="general,faketls,youtube,discord,gv"
    [ -z "$ALL_COMBOS" ]         && ALL_COMBOS="0"
    [ -z "$VPN_SECTION" ]        && VPN_SECTION="none"
    [ -z "$ONLY_STRAT_UPDATE" ]  && ONLY_STRAT_UPDATE="1"
    [ -z "$DISABLE_UPDATES" ]    && DISABLE_UPDATES="0"
    [ -z "$INCLUDE_ZM_DOMAINS" ] && INCLUDE_ZM_DOMAINS="1"
    [ -z "$CUSTOM_STRATEGY" ]    && CUSTOM_STRATEGY=""
    [ -z "$FOLLOW_ENABLED" ]     && FOLLOW_ENABLED="0"
    [ -z "$FOLLOW_FROM" ]        && FOLLOW_FROM=""

    # нормализация bool-строк
    case "$INCLUDE_ZM_DOMAINS" in
        0|false|no|off|"") INCLUDE_ZM_DOMAINS="0" ;;
        *) INCLUDE_ZM_DOMAINS="1" ;;
    esac
}

log_ux() {
    local pct="$1" tag="$2" msg="$3"
    printf "[%s] [%3s%%] [%s] %s\n" "$(date '+%H:%M:%S')" "$pct" "$tag" "$msg" >> "$LOG_FILE"
}

get_first_zapret_section_strategy() {
    local sections="$1"
    local zapret_secs=$(/bin/sh "$PARSER" --filter-zapret-sections "$sections")
    local first_sec=$(echo "$zapret_secs" | awk '{print $1}')
    [ -z "$first_sec" ] && return 1

    local fk_conf="/etc/config/forkop"
    [ ! -f "$fk_conf" ] && [ -f "/etc/config/podkop" ] && fk_conf="/etc/config/podkop"
    local pkg=$(basename "$fk_conf")

    local cur_strat=""
    cur_strat=$(uci -q get "${pkg}.${first_sec}.nfqws_opt" 2>/dev/null)
    if [ -z "$cur_strat" ] || [ "$cur_strat" = "none" ]; then
        cur_strat=$(uci -q get "${pkg}.${first_sec}.zapret_strategy" 2>/dev/null)
    fi
    cur_strat=$(echo "$cur_strat" | tr '\r\n' ' ' | sed 's/[[:space:]]\+/ /g')

    case "$cur_strat" in
        *--filter-tcp=443*|*--filter-tcp=80*|*--filter-tcp=80,443*) ;;
        *)
            log_ux 8 "WARN" "Стратегия из секции [$first_sec] не содержит TCP 443/80 — невалидна."
            return 1
            ;;
    esac
    case "$cur_strat" in
        *--dpi-desync=split2*)
            case "$cur_strat" in
                *--dpi-desync-split-seqovl-pattern*|*--dpi-desync-fake-tls*) ;;
                *)
                    log_ux 8 "WARN" "Стратегия из секции [$first_sec] содержит split2 без паттерна — невалидна."
                    return 1
                    ;;
            esac
            ;;
    esac

    ACTIVE_SEC_NAME="$first_sec"
    ACTIVE_SEC_STRAT="$cur_strat"
    return 0
}

fetch_url_to_file() {
    local url="$1"
    local dst="$2"
    local dl_opt=""

    if [ -n "$VPN_SECTION" ] && [ "$VPN_SECTION" != "none" ]; then
        local fk_conf="/etc/config/forkop"
        [ ! -f "$fk_conf" ] && [ -f "/etc/config/podkop" ] && fk_conf="/etc/config/podkop"
        local pkg=$(basename "$fk_conf")
        local vpn_if=$(uci -q get "${pkg}.${VPN_SECTION}.interface" 2>/dev/null)
        local mport=$(uci -q get "${pkg}.${VPN_SECTION}.mixed_proxy_port" 2>/dev/null)
        if [ -n "$vpn_if" ]; then
            local l3_dev=$(ifstatus "$vpn_if" 2>/dev/null | sed -n 's/.*"l3_device":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
            [ -z "$l3_dev" ] && l3_dev="$vpn_if"
            ip link show "$l3_dev" >/dev/null 2>&1 && dl_opt="--interface $l3_dev"
        fi
        if [ -z "$dl_opt" ]; then
            if [ -n "$mport" ]; then
                dl_opt="-x socks5h://127.0.0.1:$mport"
            elif netstat -tlpn 2>/dev/null | grep -q ":1080 "; then
                dl_opt="-x socks5h://127.0.0.1:1080"
            elif netstat -tlpn 2>/dev/null | grep -q ":2080 "; then
                dl_opt="-x socks5h://127.0.0.1:2080"
            fi
        fi
    fi

    curl -fsSL -k $dl_opt --connect-timeout 6 --max-time 15 -A "Mozilla/5.0" "$url" -o "$dst" 2>/dev/null && [ -s "$dst" ] && return 0
    curl -fsSL -k --connect-timeout 5 --max-time 12 -A "Mozilla/5.0" "$url" -o "$dst" 2>/dev/null && [ -s "$dst" ] && return 0
    return 1
}

silence_standalone_zapret() {
    if [ -x /etc/init.d/zapret ]; then
        /etc/init.d/zapret stop >/dev/null 2>&1
        /etc/init.d/zapret disable >/dev/null 2>&1
    fi
    for tbl in $(nft list tables 2>/dev/null | awk '{print $2 ":" $3}' | grep -iE ':zapret$|:zapret2$'); do
        local fam=$(echo "$tbl" | cut -d: -f1)
        local tname=$(echo "$tbl" | cut -d: -f2)
        nft delete table "$fam" "$tname" 2>/dev/null
    done
}

sanitize_os_params() {
    echo "$1" | sed -E \
        -e 's/--dpi-desync-fooling=ts,md5sig/--dpi-desync-fooling=md5sig/g' \
        -e 's/--dpi-desync-fooling=md5sig,ts/--dpi-desync-fooling=md5sig/g' \
        -e 's/--dpi-desync-fooling=ts,badseq/--dpi-desync-fooling=badseq,md5sig/g' \
        -e 's/--dpi-desync-fooling=badseq,ts/--dpi-desync-fooling=badseq,md5sig/g' \
        -e 's/--dpi-desync-fooling=ts\b/--dpi-desync-fooling=md5sig/g'
}

update_fake_bins() {
    [ "$DISABLE_UPDATES" = "1" ] && {
        log_ux 6 "INFO" "Обновление из интернета отключено — используются локальные файлы."
        return 0
    }
    mkdir -p /opt/zapret/files/fake
    local force_bin=0
    [ "$ONLY_STRAT_UPDATE" = "0" ] && force_bin=1

    if [ "$force_bin" = "1" ]; then
        log_ux 6 "INFO" "Принудительное обновление всех fake-бинарников (VPN: $VPN_SECTION)..."
    fi
    for f in stun.bin stun2.bin quic_initial_tencent_com.bin quic_initial_steamcommunity_com.bin \
             tls_clienthello_sochi_park.bin quic_initial_4pda_to.bin quic_initial_5ka_ru.bin \
             tls_clienthello_5ka_ru.bin quic_initial_rutube_ru.bin tls_clienthello_www_onetrust_com.bin \
             tls_clienthello_www_google_com.bin quic_initial_www_google_com.bin 4pda.bin; do
        if [ "$force_bin" = "1" ] || [ ! -s "/opt/zapret/files/fake/$f" ]; then
            fetch_url_to_file "${GH_MAIN}/Flowseal/zapret-discord-youtube/raw/refs/heads/main/bin/$f" "/opt/zapret/files/fake/$f"
        fi
    done
}

resolve_domain_ip() {
    local dom="$1"
    local ip=""
    if [ -s "$IP_CACHE_FILE" ]; then
        ip=$(awk -F'|' -v d="$dom" '$1 == d {print $2; exit}' "$IP_CACHE_FILE")
        [ -n "$ip" ] && { echo "$ip"; return 0; }
    fi
    [ -z "$DNS_SERVERS" ] && DNS_SERVERS="${DNS_PROTO:-doh}|${DNS_SERVER:-1.1.1.1}"
    local entry proto addr doh_endpoint udp_srv
    for entry in $DNS_SERVERS; do
        proto=$(echo "$entry" | cut -d'|' -f1)
        addr=$(echo "$entry" | cut -d'|' -f2)
        [ -z "$addr" ] && addr="$entry"
        ip=""
        case "$proto" in
            doh)
                doh_endpoint="https://1.1.1.1/dns-query"
                case "$addr" in
                    8.8.8.8|8.8.4.4|*google*) doh_endpoint="https://8.8.8.8/resolve" ;;
                    9.9.9.9|*quad9*)          doh_endpoint="https://9.9.9.9:5053/dns-query" ;;
                    http*)                    doh_endpoint="$addr" ;;
                esac
                ip=$(curl -s -k -H "accept: application/dns-json" --connect-timeout 2 --max-time 3 \
                    "${doh_endpoint}?name=${dom}&type=A" 2>/dev/null | \
                    grep -oE '"data"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | \
                    grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
                    grep -vE '^(127\.|0\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|198\.18\.)' | head -n1)
                ;;
            dot)
                ip=$(dig +tls +short "$dom" @"$addr" 2>/dev/null | \
                    grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
                    grep -vE '^(127\.|0\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|198\.18\.)' | head -n1)
                ;;
            *)
                udp_srv=$(echo "$addr" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
                [ -z "$udp_srv" ] && udp_srv="1.1.1.1"
                ip=$(nslookup "$dom" "$udp_srv" 2>/dev/null | tail -n +3 | \
                    grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
                    grep -vE "^(${udp_srv}|127\.|0\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|198\.18\.)" | head -n1)
                ;;
        esac
        if [ -n "$ip" ]; then
            echo "${dom}|${ip}" >> "$IP_CACHE_FILE"
            echo "$ip"
            return 0
        fi
    done
    ip=$(nslookup "$dom" 2>/dev/null | tail -n +3 | \
        grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
        grep -vE '^(127\.|0\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|198\.18\.)' | head -n1)
    if [ -n "$ip" ]; then
        echo "${dom}|${ip}" >> "$IP_CACHE_FILE"
        echo "$ip"
        return 0
    fi
    return 1
}

cleanup_sandbox() {
    [ -n "$SANDBOX_PID" ] && kill -9 "$SANDBOX_PID" 2>/dev/null
    kill_matching "nfqws.*--qnum=$SANDBOX_QNUM"
    nft delete table inet "$SANDBOX_TABLE" 2>/dev/null

    for ftbl in $(nft list tables 2>/dev/null | awk '{print $2 ":" $3}'); do
        local ffam=$(echo "$ftbl" | cut -d: -f1)
        local fname=$(echo "$ftbl" | cut -d: -f2)
        for fch in $(nft list table "$ffam" "$fname" 2>/dev/null | awk '/chain /{print $2}'); do
            for hdl in $(nft -a list chain "$ffam" "$fname" "$fch" 2>/dev/null | grep "FZ_BYPASS" | awk '{print $NF}'); do
                nft delete rule "$ffam" "$fname" "$fch" handle "$hdl" 2>/dev/null
            done
        done
    done
}

on_exit() {
    cleanup_sandbox   # ИСПРАВЛЕНО: раньше был закомментирован — приводило к утечке nft/queue между прогонами
    rm -f "$LOCK_FILE" "$STOP_FLAG"
}

flush_test_ips_from_forkop_sets() {
    [ ! -s "$IP_CACHE_FILE" ] && return 0
    local ips=$(cut -d'|' -f2 "$IP_CACHE_FILE" | sort -u)
    for ftbl in $(nft list tables 2>/dev/null | awk '/forkop|podkop/{print $2 ":" $3}'); do
        local ffam=$(echo "$ftbl" | cut -d: -f1)
        local fname=$(echo "$ftbl" | cut -d: -f2)
        for sname in $(nft list table "$ffam" "$fname" 2>/dev/null | awk '/^[[:space:]]*set /{print $2}'); do
            for tip in $ips; do
                nft delete element "$ffam" "$fname" "$sname" "{ $tip }" 2>/dev/null
            done
        done
    done
}

setup_isolated_channel() {
    local strat_args="$1"
    cleanup_sandbox
    # Настройки уже загружены в run_main с конкретной секцией.
    # Повторный load_settings без аргументов перетирал бы выбранные
    # категории/DNS/VPN глобальными значениями (general,gv и т.п.).
    flush_test_ips_from_forkop_sets

    for fch in output mangle_output mangle_postrouting; do
        nft insert rule inet fw4 "$fch" 'meta mark & 0x40000000 != 0 accept comment "FZ_BYPASS"' 2>/dev/null
    done
    for ftbl in $(nft list tables 2>/dev/null | awk '/forkop|podkop/{print $2 ":" $3}'); do
        local ffam=$(echo "$ftbl" | cut -d: -f1)
        local fname=$(echo "$ftbl" | cut -d: -f2)
        for fch in $(nft list table "$ffam" "$fname" 2>/dev/null | awk '/chain /{print $2}'); do
            nft insert rule "$ffam" "$fname" "$fch" 'meta mark & 0x40000000 != 0 return comment "FZ_BYPASS"' 2>/dev/null
            nft insert rule "$ffam" "$fname" "$fch" "meta mark $SANDBOX_MARK return comment \"FZ_BYPASS\"" 2>/dev/null
            nft insert rule "$ffam" "$fname" "$fch" 'meta mark 0x4000029a return comment "FZ_BYPASS"' 2>/dev/null
        done
    done

    if [ -n "$strat_args" ]; then
        nft add table inet "$SANDBOX_TABLE"
        nft add set inet "$SANDBOX_TABLE" test_ips "{ type ipv4_addr; }"
        if [ -s "$IP_CACHE_FILE" ]; then
            for tip in $(cut -d'|' -f2 "$IP_CACHE_FILE" | sort -u); do
                nft add element inet "$SANDBOX_TABLE" test_ips "{ $tip }"
            done
        fi
        nft add chain inet "$SANDBOX_TABLE" output "{ type filter hook output priority -150; policy accept; }"
        nft add rule inet "$SANDBOX_TABLE" output 'meta mark & 0x40000000 != 0 return'
        nft add rule inet "$SANDBOX_TABLE" output "ip daddr @test_ips tcp dport { 80, 443, 2053, 2083, 2087, 2096, 8443 } ct original packets 1-9 meta mark set $SANDBOX_MARK"

        nft add chain inet "$SANDBOX_TABLE" postrouting "{ type filter hook postrouting priority 105; policy accept; }"
        nft add rule inet "$SANDBOX_TABLE" postrouting 'meta mark & 0x40000000 != 0 return'
        nft add rule inet "$SANDBOX_TABLE" postrouting "meta mark $SANDBOX_MARK meta l4proto tcp counter queue num $SANDBOX_QNUM bypass"

        eval "$NFQWS_BIN --qnum=$SANDBOX_QNUM --dpi-desync-fwmark=0x40000000 $strat_args" > "$WORK_DIR/nfqws_err.log" 2>&1 &
        SANDBOX_PID=$!
        sleep 1
    fi
}

# === УСКОРЕННАЯ ПРОВЕРКА (проблема №1) ===
# Один основной запрос с --speed-limit/--speed-time (детектор заморозки ТСПУ).
# JS докачиваем ТОЛЬКО если HTML < 5 КБ (SPA-оболочки) и в нём есть <script src>.
# Отключение: скорость < 3 КБ/с в течение 2 сек → FREEZE; нет соединения → FAIL.
deep_browser_load_check() {
    local dom="$1"
    local ip="$2"
    local iface_opt=""
    [ -n "$WAN_DEV" ] && iface_opt="--interface $WAN_DEV"
    local html_tmp="$WORK_DIR/h_${dom}.$$"

    local out
    out=$(curl -s $iface_opt --resolve "${dom}:443:${ip}" \
        --connect-timeout 3 --max-time 5 \
        --speed-limit "$SPEED_LIMIT_PAGE" --speed-time "$SPEED_TIME_PAGE" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        -H "Cache-Control: no-cache" \
        -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" \
        -w "%{http_code}|%{time_connect}|%{size_download}" \
        -o "$html_tmp" "https://${dom}/" 2>/dev/null)
    local rc=$?
    local http_code=$(echo "$out" | cut -d'|' -f1)
    local t_conn=$(echo "$out" | cut -d'|' -f2)
    local size=$(echo "$out" | cut -d'|' -f3)

    # 1) Таймаут при передаче — это ровно заморозка ТСПУ
    if [ "$rc" -eq 28 ]; then
        rm -f "$html_tmp"
        echo "FREEZE|$t_conn"; return 1
    fi
    # 2) Соединение не установилось / обрыв
    if [ "$rc" -ne 0 ] || [ "$http_code" = "000" ] || [ -z "$http_code" ]; then
        rm -f "$html_tmp"
        echo "FAIL|$t_conn"; return 1
    fi
    # 3) HTTP 403/451 от DPI-шлюза
    case "$http_code" in
        403|451) rm -f "$html_tmp"; echo "FREEZE|$t_conn"; return 1 ;;
    esac

    # 4) Всегда проверяем ключевые same-origin подресурсы (JS/CSS).
    #    Это ловит «частичную блокировку»: HTML отдаёт 200, а бандл висит
    #    в pending (ТСПУ замораживает поток), и старый код ставил ложный OK.
    local sub_js="" sub_css=""
    if [ -s "$html_tmp" ]; then
        sub_js=$(grep -oE 'src="[^"]+\.js[^"]*"' "$html_tmp" 2>/dev/null | head -n1 | sed 's/^src="//; s/"$//')
        sub_css=$(grep -oE 'href="[^"]+\.css[^"]*"' "$html_tmp" 2>/dev/null | head -n1 | sed 's/^href="//; s/"$//')
    fi
    rm -f "$html_tmp"

    local sub_src sub_url
    for sub_src in "${sub_js:-}" "${sub_css:-}"; do
        [ -z "$sub_src" ] && continue
        case "$sub_src" in
            https://*|http://*) sub_url="$sub_src" ;;
            //*) sub_url="https:$sub_src" ;;
            /*)  sub_url="https://${dom}${sub_src}" ;;
            *)   sub_url="https://${dom}/${sub_src}" ;;
        esac
        # Проверяем только same-origin (для cross-origin --resolve бесполезен)
        case "$sub_url" in
            "https://${dom}/"*|"http://${dom}/"*) ;;
            *) continue ;;
        esac
        local sub_hdr="$WORK_DIR/sh_${dom}.$$.hdr"
        local sub_out
        sub_out=$(curl -s $iface_opt --resolve "${dom}:443:${ip}" \
            --connect-timeout 3 --max-time 6 \
            --speed-limit "$SPEED_LIMIT_JS" --speed-time "$SPEED_TIME_JS" \
            -A "Mozilla/5.0" -D "$sub_hdr" -w "%{http_code}|%{size_download}" -o /dev/null "$sub_url" 2>/dev/null)
        local sub_rc=$?
        local sub_code=$(echo "$sub_out" | cut -d'|' -f1)
        local sub_size=$(echo "$sub_out" | cut -d'|' -f2)
        local sub_clen=$(awk 'tolower($1)=="content-length:"{v=$2} END{print v}' "$sub_hdr" 2>/dev/null | tr -d '\r')
        rm -f "$sub_hdr"
        [ "$sub_rc" -eq 28 ] && { echo "FREEZE|$t_conn"; return 1; }
        if [ "$sub_rc" -ne 0 ] || [ "$sub_code" = "000" ] || [ -z "$sub_code" ]; then
            echo "FREEZE|$t_conn"; return 1
        fi
        case "$sub_code" in 403|451|5*) echo "FREEZE|$t_conn"; return 1 ;; esac
        if [ -n "$sub_clen" ] && [ "${sub_size:-0}" -lt "$sub_clen" ]; then
            echo "FREEZE|$t_conn"; return 1
        fi
        if [ "${sub_size:-0}" -lt 500 ]; then
            echo "FREEZE|$t_conn"; return 1
        fi
    done

    echo "OK|$t_conn"
    return 0
}

diagnose_domain_baseline() {
    local dom="$1"
    local ip="$2"
    local iface_opt=""
    [ -n "$WAN_DEV" ] && iface_opt="--interface $WAN_DEV"

    if [ -z "$ip" ]; then echo "DNS_FAIL"; return; fi

    local res=$(deep_browser_load_check "$dom" "$ip")
    local status=$(echo "$res" | cut -d'|' -f1)
    local t_conn=$(echo "$res" | cut -d'|' -f2)

    [ "$status" = "OK" ]     && { echo "OK"; return; }
    [ "$status" = "FREEZE" ] && { echo "DPI_BLOCK_FREEZE"; return; }

    # Если не соединились вообще — проверяем, живёт ли IP с белым SNI
    case "$t_conn" in
        0|0.000*|0,000*|"")
            local sni_out=$(curl -sI -k $iface_opt --resolve "ya.ru:443:${ip}" \
                --connect-timeout 2 --max-time 3 -w "%{http_code}|%{time_connect}" \
                -o /dev/null "https://ya.ru/" 2>/dev/null)
            local sni_tconn=$(echo "$sni_out" | cut -d'|' -f2)
            case "$sni_tconn" in
                0|0.000*|0,000*|"") echo "TSPU_IP_BLOCK|$ip"; return ;;
                *)                  echo "DPI_BLOCK";          return ;;
            esac
            ;;
        *) echo "DPI_BLOCK"; return ;;
    esac
}

test_domain_strategy() {
    local dom="$1"
    local ip=$(awk -F'|' -v d="$dom" '$1 == d {print $2; exit}' "$IP_CACHE_FILE")
    [ -z "$ip" ] && return 1
    local res=$(deep_browser_load_check "$dom" "$ip")
    [ "$(echo "$res" | cut -d'|' -f1)" = "OK" ] && return 0
    return 1
}

evaluate_section_domains_only() {
    local sec_domains="$1"
    local pct="$2"
    local sec_ok_file="$WORK_DIR/sec_only_ok.$$"
    : > "$sec_ok_file"
    local job_cnt=0
    for d in $sec_domains; do
        [ -f "$STOP_FLAG" ] && break
        (
            if test_domain_strategy "$d"; then
                echo 1 >> "$sec_ok_file"
                log_ux "$pct" "SEC_OK" "★ [СЕКЦИЯ] $d — ДОСТУПЕН"
            else
                log_ux "$pct" "SEC_FAIL" "✗ [СЕКЦИЯ] $d — БЛОК DPI / заморозка"
            fi
        ) &
        job_cnt=$((job_cnt + 1))
        if [ "$job_cnt" -ge "$PARALLEL_CURL" ]; then wait; job_cnt=0; fi
    done
    wait
    local s_ok=$(wc -l < "$sec_ok_file" 2>/dev/null | tr -d ' ')
    rm -f "$sec_ok_file"
    echo "${s_ok:-0}"
}

evaluate_zm_domains_only() {
    local zm_domains="$1"
    local pct="$2"
    local zm_ok_file="$WORK_DIR/zm_only_ok.$$"
    : > "$zm_ok_file"
    local job_cnt=0
    for d in $zm_domains; do
        [ -f "$STOP_FLAG" ] && break
        (
            if test_domain_strategy "$d"; then
                echo 1 >> "$zm_ok_file"
                log_ux "$pct" "ZM_OK" "  ✓ [БАЗА ZM] $d — доступен"
            else
                log_ux "$pct" "ZM_FAIL" "  · [БАЗА ZM] $d — блок"
            fi
        ) &
        job_cnt=$((job_cnt + 1))
        if [ "$job_cnt" -ge "$PARALLEL_CURL" ]; then wait; job_cnt=0; fi
    done
    wait
    local z_ok=$(wc -l < "$zm_ok_file" 2>/dev/null | tr -d ' ')
    rm -f "$zm_ok_file"
    echo "${z_ok:-0}"
}

evaluate_domains_split() {
    local sec_domains="$1"
    local zm_domains="$2"
    local pct="$3"
    local s_ok=$(evaluate_section_domains_only "$sec_domains" "$pct")
    local z_ok=0
    [ -n "$zm_domains" ] && z_ok=$(evaluate_zm_domains_only "$zm_domains" "$pct")
    echo "${s_ok:-0}:${z_ok:-0}"
}

cron_express_verify_active_forkop() {
    local valid_domains="$1"
    local sections="$2"
    local total=$(echo "$valid_domains" | wc -w | tr -d ' ')
    [ "${total:-0}" -eq 0 ] && return 1
    if ! get_first_zapret_section_strategy "$sections"; then return 1; fi

    log_ux 8 "STAGE" "═══ CRON: Проверка текущей стратегии [$ACTIVE_SEC_NAME] на $total доменах ═══"
    setup_isolated_channel "$ACTIVE_SEC_STRAT"
    local ok_cnt=$(evaluate_section_domains_only "$valid_domains" 9)
    cleanup_sandbox

    if [ "$ok_cnt" -eq "$total" ]; then
        /etc/init.d/dnsmasq reload >/dev/null 2>&1
        log_ux 100 "BEST" "✅ [CRON] Все $ok_cnt/$total доменов открываются на текущей стратегии [$ACTIVE_SEC_NAME]. Подбор не требуется."
        return 0
    fi
    log_ux 10 "WARN" "⚠️ [CRON] Открылось $ok_cnt из $total — запускаем полный подбор."
    return 1
}

manual_verify_current_active_strategy() {
    local sections="$1"
    [ "$SEC_COUNT" -le 0 ] && return 1
    if ! get_first_zapret_section_strategy "$sections"; then
        log_ux 8 "INFO" "Стратегия не задана — переходим к полному перебору."
        return 1
    fi
    log_ux 8 "INFO" "Текущая стратегия [$ACTIVE_SEC_NAME]: ${ACTIVE_SEC_STRAT:0:50}..."

    log_ux 8 "STAGE" "═══ Проверка №1: текущая стратегия секции [$ACTIVE_SEC_NAME] ═══"
    setup_isolated_channel "$ACTIVE_SEC_STRAT"
    local s_ok=$(evaluate_section_domains_only "$SEC_DOMAINS" 9)

    if [ "$s_ok" -eq "$SEC_COUNT" ]; then
        log_ux 9 "BEST" "✅ Все домены секции ($s_ok/$SEC_COUNT) работают на текущей стратегии!"
        local z_ok=0
        if [ "$INCLUDE_ZM_DOMAINS" = "1" ] && [ "$ZM_COUNT" -gt 0 ]; then
            z_ok=$(evaluate_zm_domains_only "$ZM_DOMAINS" 10)
        fi
        cleanup_sandbox
        local tot_ok=$((s_ok + z_ok))
        local diff_ctrl=$((tot_ok - CTRL_TOTAL_OK)); [ "$diff_ctrl" -ge 0 ] && diff_ctrl="+$diff_ctrl"
        /etc/init.d/dnsmasq reload >/dev/null 2>&1
        if [ "$ZM_COUNT" -gt 0 ] && [ "$INCLUDE_ZM_DOMAINS" = "1" ]; then
            log_ux 98 "RESULT" "◼ ТЕКУЩАЯ [$ACTIVE_SEC_NAME] ➔ Секции: $s_ok/$SEC_COUNT | ZM: $z_ok/$ZM_COUNT | Всего: $tot_ok/$DOM_COUNT ($diff_ctrl)"
        else
            log_ux 98 "RESULT" "◼ ТЕКУЩАЯ [$ACTIVE_SEC_NAME] ➔ Домены секции: $s_ok/$SEC_COUNT ($diff_ctrl)"
        fi
        if [ "$ZM_COUNT" -eq 0 ] || [ "$tot_ok" -gt "$CTRL_TOTAL_OK" ]; then
            log_ux 100 "BEST" "🏆 Текущая стратегия полностью исправна. Перебор остановлен."
            return 0
        fi
        log_ux 10 "WARN" "⚠️ Все домены секции OK, но нет прироста по ZM ($tot_ok/$CTRL_TOTAL_OK) — продолжаем подбор..."
        return 1
    fi
    cleanup_sandbox
    log_ux 10 "WARN" "⚠️ Текущая стратегия открыла $s_ok/$SEC_COUNT. Продолжаем подбор..."
    return 1
}

# ================= Кастомная стратегия =================
test_custom_strategy() {
    local auto_apply="$1"
    local sections="$2"
    [ -z "$CUSTOM_STRATEGY" ] && return 1

    log_ux 8 "STAGE" "═══ ЭТАП 0.5: Проверка КАСТОМНОЙ стратегии пользователя ═══"
    setup_isolated_channel "$CUSTOM_STRATEGY"
    local c_ok=$(evaluate_section_domains_only "$SEC_DOMAINS" 9)
    local cz_ok=0
    if [ "$INCLUDE_ZM_DOMAINS" = "1" ] && [ "$ZM_COUNT" -gt 0 ]; then
        cz_ok=$(evaluate_zm_domains_only "$ZM_DOMAINS" 9)
    fi
    cleanup_sandbox
    local ct=$((c_ok + cz_ok))
    printf "%d|%d|%s|%s\n" "$c_ok" "$ct" "Custom_UserStrategy" "$CUSTOM_STRATEGY" >> "$RESULTS_FILE"
    log_ux 9 "RESULT" "◼ КАСТОМ ➔ Секции: $c_ok/$SEC_COUNT | Всего: $ct/$DOM_COUNT"

    if [ "$c_ok" -gt "$GLOBAL_BEST_SEC" ] || { [ "$c_ok" -eq "$GLOBAL_BEST_SEC" ] && [ "$ct" -gt "$GLOBAL_BEST_TOT" ]; }; then
        GLOBAL_BEST_SEC="$c_ok"; GLOBAL_BEST_TOT="$ct"
        GLOBAL_BEST_NAME="Custom_UserStrategy"; GLOBAL_BEST_BODY="$CUSTOM_STRATEGY"
    fi

    if [ "$c_ok" -eq "$SEC_COUNT" ]; then
        if [ "$ZM_COUNT" -eq 0 ] || [ "$ct" -gt "$CTRL_TOTAL_OK" ]; then
            log_ux 100 "BEST" "🏆 Кастомная стратегия даёт 100% по доменам секции и прирост по ZM!"
            if [ "$auto_apply" = "1" ]; then
                atomic_apply_strategy "Custom_UserStrategy" "$CUSTOM_STRATEGY" "$sections"
            fi
            return 0
        fi
        log_ux 10 "WARN" "⚠️ Кастомная: все домены секции OK, но нет прироста по ZM ($ct/$CTRL_TOTAL_OK) — продолжаем."
    fi
    return 1
}

# ================= Быстрый гибрид (проблема №3) =================
test_quick_hybrid() {
    local sections="$1"
    local auto_apply="$2"
    [ "$GLOBAL_BEST_SEC" -ge "$SEC_COUNT" ] && return 1
    local cat_cnt=$(echo "$STRAT_CATS" | tr ',' '\n' | grep -c '.')
    [ "$cat_cnt" -le 1 ] && return 1
    [ -s "$CAT_GENERAL" ] || return 1

    log_ux 9 "STAGE" "═══ ЭТАП 1.5: Быстрый гибрид (сразу смесь всех выбранных групп) ═══"
    local h_gen=$(head -n1 "$CAT_GENERAL" 2>/dev/null | cut -d'|' -f2)
    local h_yt=""; [ -s "$CAT_YOUTUBE" ] && h_yt=$(head -n1 "$CAT_YOUTUBE" | cut -d'|' -f2)
    local h_disc=""; [ -s "$CAT_DISCORD" ] && h_disc=$(head -n1 "$CAT_DISCORD" | cut -d'|' -f2)
    local h_gv=""; [ -s "$CAT_GV" ] && h_gv=$(head -n1 "$CAT_GV" | cut -d'|' -f2)

    local hybrid=$(assemble_combo_strategy "$h_gen" "$h_yt" "$h_disc" "" "$h_gv")
    setup_isolated_channel "$hybrid"
    local h_ok=$(evaluate_section_domains_only "$SEC_DOMAINS" 10)
    local hz_ok=0
    if [ "$INCLUDE_ZM_DOMAINS" = "1" ] && [ "$ZM_COUNT" -gt 0 ]; then
        hz_ok=$(evaluate_zm_domains_only "$ZM_DOMAINS" 10)
    fi
    cleanup_sandbox
    local ht=$((h_ok + hz_ok))
    printf "%d|%d|%s|%s\n" "$h_ok" "$ht" "Quick_Hybrid_All" "$hybrid" >> "$RESULTS_FILE"
    log_ux 11 "RESULT" "◼ БЫСТРЫЙ ГИБРИД ➔ Секции: $h_ok/$SEC_COUNT | Всего: $ht/$DOM_COUNT"

    if [ "$h_ok" -gt "$GLOBAL_BEST_SEC" ] || { [ "$h_ok" -eq "$GLOBAL_BEST_SEC" ] && [ "$ht" -gt "$GLOBAL_BEST_TOT" ]; }; then
        GLOBAL_BEST_SEC="$h_ok"; GLOBAL_BEST_TOT="$ht"
        GLOBAL_BEST_NAME="Quick_Hybrid_All"; GLOBAL_BEST_BODY="$hybrid"
    fi

    if [ "$h_ok" -eq "$SEC_COUNT" ]; then
        log_ux 100 "BEST" "🏆 Гибрид всех групп покрывает 100% доменов!"
        if [ "$auto_apply" = "1" ]; then
            atomic_apply_strategy "Quick_Hybrid_All" "$hybrid" "$sections"
        fi
        return 0
    fi
    return 1
}

assemble_combo_strategy() {
    local c443=$(sanitize_os_params "$1")
    local yt=$(sanitize_os_params "$2")
    local dtcp=$(sanitize_os_params "$3")
    local dudp="$4"
    local gv="$5"

    [ -z "$c443" ] && c443="--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-fooling=md5sig --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"
    local c80_443=$(echo "$c443" | sed 's/^--filter-tcp=443/--filter-tcp=80,443/')
    [ -z "$dtcp" ] && dtcp=$(echo "$c443" | sed 's/^--filter-tcp=443/--filter-tcp=2053,2083,2087,2096,8443/')
    [ -z "$dudp" ] && dudp="--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-fake-discord=/opt/zapret/files/fake/quic_initial_steamcommunity_com.bin --dpi-desync-fake-stun=/opt/zapret/files/fake/quic_initial_steamcommunity_com.bin --dpi-desync-repeats=6"
    [ -z "$gv" ] && gv="--filter-udp=$PORTS_UDP --dpi-desync=fake --dpi-desync-cutoff=d2 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin --new --filter-tcp=$PORTS_TCP --dpi-desync-any-protocol=1 --dpi-desync-cutoff=n5 --dpi-desync=multisplit --dpi-desync-split-seqovl=582 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin"

    local main_443="$c443"
    [ -n "$yt" ] && main_443="$yt"

    echo "$dudp --new $dtcp --new $main_443 --new $c80_443 --new $gv" | sed 's/[[:space:]]\+/ /g'
}

prepare_categorized_strategies() {
    : > "$CAT_GENERAL"; : > "$CAT_FAKETLS"; : > "$CAT_YOUTUBE"; : > "$CAT_DISCORD"; : > "$CAT_GV"
    log_ux 11 "STAGE" "═══ ЭТАП 1: Подготовка категорий ($STRAT_CATS) ═══"
    update_fake_bins

    cat << 'EOF' >> "$CAT_GENERAL"
General_v1_Split2|--filter-tcp=443 --dpi-desync=split2 --dpi-desync-split-seqovl=681 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin
General_v2_Multisplit_MD5|--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-fooling=md5sig --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com
General_v3_HostFake_Ozon|--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=ozon.ru --dpi-desync-repeats=4 --dpi-desync-fooling=md5sig --dpi-desync-badseq-increment=0
General_v4_Multisplit_582|--filter-tcp=443 --dpi-desync=multisplit --dpi-desync-split-seqovl=582 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin
General_v5_Disorder_Badseq|--filter-tcp=443 --dpi-desync=fake,fakeddisorder --dpi-desync-split-pos=1 --dpi-desync-fake-tls=/opt/zapret/files/fake/stun.bin --dpi-desync-fake-tls-mod=none --dpi-desync-fakedsplit-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fooling=badseq,badsum --dpi-desync-badseq-increment=0
General_v6_HostFake_2GIS|--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=i2.photo.2gis.com --dpi-desync-hostfakesplit-midhost=host-2 --dpi-desync-split-seqovl=726 --dpi-desync-fooling=badsum,badseq --dpi-desync-badseq-increment=0
General_v7_Multisplit_654|--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=654 --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq,badsum --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/stun.bin --dpi-desync-badseq-increment=0
General_v8_Fake_4PDA|--filter-tcp=443 --dpi-desync=fake --dpi-desync-fooling=md5sig --dpi-desync-fake-tls=/opt/zapret/files/fake/4pda.bin --dpi-desync-fake-tls-mod=none
General_v9_HostFake_Badsum|--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-fooling=badseq,badsum --dpi-desync-hostfakesplit-mod=host=ozon.ru --dpi-desync-badseq-increment=0
General_v10_FakeSplit2_MaxCDN|--filter-tcp=443 --dpi-desync=fake,split2 --dpi-desync-split-pos=2 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-hostfakesplit-mod=host=maxcdn.bootstrapcdn.com --dpi-desync-fake-tls-mod=rnd,sni=maxcdn.bootstrapcdn.com --dpi-desync-fooling=md5sig
General_v11_Forkop_OneTrust|--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=664 --dpi-desync-split-pos=1 --dpi-desync-fooling=md5sig --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_onetrust_com.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/stun2.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_onetrust_com.bin
EOF

    cat << 'EOF' >> "$CAT_FAKETLS"
FakeTLS_Google_MD5|--filter-tcp=443 --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=none
FakeTLS_Multisplit_Badseq1000|--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=1000 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
FakeTLS_SNIExt_679|--filter-tcp=443 --dpi-desync=multisplit --dpi-desync-split-pos=2,sniext+1 --dpi-desync-split-seqovl=679 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
FakeTLS_FakedSplit_Badseq2|--filter-tcp=443 --dpi-desync=fake,fakedsplit --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --dpi-desync-repeats=8 --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com
FakeTLS_Multisplit_Badseq10M|--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=10000000 --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com
FakeTLS_Pattern00_MD5|--filter-tcp=443 --dpi-desync=fake,fakedsplit --dpi-desync-repeats=6 --dpi-desync-fooling=md5sig --dpi-desync-fakedsplit-pattern=0x00 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
FakeTLS_Multidisorder_MidSLD|--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=11 --dpi-desync-fooling=badseq --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com
FakeTLS_HostFake_AltOrder|--filter-tcp=443 --dpi-desync=fake,hostfakesplit --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com --dpi-desync-hostfakesplit-mod=host=www.google.com,altorder=1 --dpi-desync-fooling=md5sig
EOF

    cat << 'EOF' >> "$CAT_YOUTUBE"
YouTube_Yv01_Multisplit|--filter-tcp=443 --dpi-desync=multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
YouTube_Yv02_SNIExt|--filter-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-pos=2,sniext+1 --dpi-desync-split-seqovl=679 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
YouTube_Yv08_HostFake|--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=google.com --dpi-desync-fooling=md5sig
EOF

    if [ "$DISABLE_UPDATES" != "1" ]; then
        log_ux 12 "INFO" "Обновление YouTube стратегий (StrYoutube)..."
        local yt_list="$WORK_DIR/str_youtube.txt"
        if fetch_url_to_file "$STR_YT_URL" "$yt_list"; then
            : > "$CAT_YOUTUBE"
            local y_name="" y_body=""
            while IFS= read -r line || [ -n "$line" ]; do
                line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                [ -z "$line" ] && continue
                case "$line" in
                    \#*)
                        if [ -n "$y_name" ] && [ -n "$y_body" ]; then
                            echo "YouTube_${y_name#\#}|$(sanitize_os_params "$y_body")" >> "$CAT_YOUTUBE"
                        fi
                        y_name="$line"; y_body=""
                        ;;
                    --hostlist=*|--ipset=*) continue ;;
                    --*) y_body="${y_body:+$y_body }$line" ;;
                esac
            done < "$yt_list"
            if [ -n "$y_name" ] && [ -n "$y_body" ]; then
                echo "YouTube_${y_name#\#}|$(sanitize_os_params "$y_body")" >> "$CAT_YOUTUBE"
            fi
            rm -f "$yt_list"
        fi
    fi

    cat << 'EOF' >> "$CAT_DISCORD"
Discord_Dv_MD5|--filter-tcp=2053,2083,2087,2096,8443 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-fooling=md5sig --dpi-desync-repeats=8 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
Discord_Dv1_Split652|--filter-tcp=2053,2083,2087,2096,8443 --dpi-desync=multisplit --dpi-desync-split-seqovl=652 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
Discord_Dv5_Badseq1000|--filter-tcp=2053,2083,2087,2096,8443 --dpi-desync=fake,multisplit --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=1000 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
Discord_Dv7_SNIExt679|--filter-tcp=2053,2083,2087,2096,8443 --dpi-desync=multisplit --dpi-desync-split-pos=2,sniext+1 --dpi-desync-split-seqovl=679 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
Discord_Dv9_FakedSplit|--filter-tcp=2053,2083,2087,2096,8443 --dpi-desync=fake,fakedsplit --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --dpi-desync-repeats=8 --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com
Discord_Dv15_Multidisorder|--filter-tcp=2053,2083,2087,2096,8443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=11 --dpi-desync-fooling=badseq --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com
EOF

    cat << EOF >> "$CAT_GV"
Game_Gv1_Cutoff_d2|--filter-udp=$PORTS_UDP --dpi-desync=fake --dpi-desync-cutoff=d2 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin --new --filter-tcp=$PORTS_TCP --dpi-desync-any-protocol=1 --dpi-desync-cutoff=n5 --dpi-desync=multisplit --dpi-desync-split-seqovl=582 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin
Game_Gv2_Cutoff_n2|--filter-udp=$PORTS_UDP --dpi-desync=fake --dpi-desync-repeats=10 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin --dpi-desync-cutoff=n2 --new --filter-tcp=$PORTS_TCP --dpi-desync-any-protocol=1 --dpi-desync-cutoff=n5 --dpi-desync=multisplit --dpi-desync-split-seqovl=582 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin
Game_Gv3_Cutoff_n3|--filter-udp=$PORTS_UDP --dpi-desync=fake --dpi-desync-repeats=10 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin --dpi-desync-cutoff=n3 --new --filter-tcp=$PORTS_TCP --dpi-desync-any-protocol=1 --dpi-desync-cutoff=n5 --dpi-desync=multisplit --dpi-desync-split-seqovl=582 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin
Game_Gv4_Cutoff_n4|--filter-udp=$PORTS_UDP --dpi-desync=fake --dpi-desync-repeats=10 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin --dpi-desync-cutoff=n4 --new --filter-tcp=$PORTS_TCP --dpi-desync-any-protocol=1 --dpi-desync-cutoff=n5 --dpi-desync=multisplit --dpi-desync-split-seqovl=582 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin
EOF
}

run_baseline_control_test() {
    local raw_sec_domains="$1"
    local raw_zm_domains="$2"

    : > "$IP_CACHE_FILE"
    log_ux 2 "STAGE" "═══ ЭТАП 0.1: Резолвинг доменов ($DNS_PROTO / $DNS_SERVER) ═══"
    local r_cnt=0
    for d in $raw_sec_domains $raw_zm_domains; do
        [ -f "$STOP_FLAG" ] && break
        resolve_domain_ip "$d" >/dev/null 2>&1 &
        r_cnt=$((r_cnt + 1))
        [ $((r_cnt % 10)) -eq 0 ] && wait
    done
    wait
    local resolved_total=$(wc -l < "$IP_CACHE_FILE" 2>/dev/null | tr -d ' ')
    log_ux 3 "INFO" "Получены IPv4 для $resolved_total доменов."

    log_ux 4 "STAGE" "═══ ЭТАП 0.2: Контроль без стратегий + классификация DPI/IP ═══"
    setup_isolated_channel ""

    VALID_SEC_DOMAINS=""; VALID_ZM_DOMAINS=""
    CTRL_SEC_OK=0; CTRL_ZM_OK=0; TSPU_BLOCKED_CNT=0

    for d in $raw_sec_domains; do
        [ -f "$STOP_FLAG" ] && break
        local dip=$(awk -F'|' -v dom="$d" '$1 == dom {print $2; exit}' "$IP_CACHE_FILE")
        local diag=$(diagnose_domain_baseline "$d" "$dip")
        case "$diag" in
            OK)
                CTRL_SEC_OK=$((CTRL_SEC_OK + 1))
                VALID_SEC_DOMAINS="${VALID_SEC_DOMAINS:+$VALID_SEC_DOMAINS }$d"
                log_ux 5 "SEC_OK" "★ [КОНТРОЛЬ] $d ($dip) — ОТКРЫВАЕТСЯ БЕЗ СТРАТЕГИЙ"
                ;;
            DPI_BLOCK_FREEZE)
                VALID_SEC_DOMAINS="${VALID_SEC_DOMAINS:+$VALID_SEC_DOMAINS }$d"
                log_ux 5 "SEC_FAIL" "🔒 [КОНТРОЛЬ] $d ($dip) — DPI-заморозка потока (лечится Zapret)"
                ;;
            DPI_BLOCK)
                VALID_SEC_DOMAINS="${VALID_SEC_DOMAINS:+$VALID_SEC_DOMAINS }$d"
                log_ux 5 "SEC_FAIL" "🔒 [КОНТРОЛЬ] $d ($dip) — DPI-блок по SNI (лечится Zapret)"
                ;;
            TSPU_IP_BLOCK*)
                TSPU_BLOCKED_CNT=$((TSPU_BLOCKED_CNT + 1))
                log_ux 5 "TSPU_WARN" "⛔ [БЛОК ПО IP] $d ($dip) — 443 глушится по IP. Исключён из тестов."
                ;;
            DNS_FAIL)
                TSPU_BLOCKED_CNT=$((TSPU_BLOCKED_CNT + 1))
                log_ux 5 "TSPU_WARN" "⛔ [DNS_FAIL] $d — нет A-записи. Исключён."
                ;;
        esac
    done
    for d in $raw_zm_domains; do
        [ -f "$STOP_FLAG" ] && break
        local dip=$(awk -F'|' -v dom="$d" '$1 == dom {print $2; exit}' "$IP_CACHE_FILE")
        local diag=$(diagnose_domain_baseline "$d" "$dip")
        case "$diag" in
            OK)
                CTRL_ZM_OK=$((CTRL_ZM_OK + 1))
                VALID_ZM_DOMAINS="${VALID_ZM_DOMAINS:+$VALID_ZM_DOMAINS }$d"
                log_ux 6 "ZM_OK" "  ✓ [ZM] $d ($dip) — открывается без стратегий"
                ;;
            DPI_BLOCK*)
                VALID_ZM_DOMAINS="${VALID_ZM_DOMAINS:+$VALID_ZM_DOMAINS }$d"
                log_ux 6 "ZM_FAIL" "  🔒 [ZM] $d ($dip) — DPI-блок/заморозка"
                ;;
            TSPU_IP_BLOCK*|DNS_FAIL)
                TSPU_BLOCKED_CNT=$((TSPU_BLOCKED_CNT + 1))
                log_ux 6 "TSPU_WARN" "  ⛔ [ZM/IP] $d (${dip:-no-ip}) — исключён"
                ;;
        esac
    done
    cleanup_sandbox

    local v_sec_cnt=$(echo "$VALID_SEC_DOMAINS" | wc -w | tr -d ' ')
    local v_zm_cnt=$(echo "$VALID_ZM_DOMAINS" | wc -w | tr -d ' ')
    local v_tot_cnt=$((v_sec_cnt + v_zm_cnt))
    CTRL_TOTAL_OK=$((CTRL_SEC_OK + CTRL_ZM_OK))

    if [ "$v_zm_cnt" -gt 0 ]; then
        log_ux 7 "RESULT" "◼ КОНТРОЛЬ ➔ Секции: $CTRL_SEC_OK/$v_sec_cnt | ZM: $CTRL_ZM_OK/$v_zm_cnt | Всего: $CTRL_TOTAL_OK/$v_tot_cnt (IP/DNS-отсеяно: $TSPU_BLOCKED_CNT)"
    else
        log_ux 7 "RESULT" "◼ КОНТРОЛЬ СЕКЦИИ ➔ Доступно напрямую: $CTRL_SEC_OK/$v_sec_cnt (IP/DNS-отсеяно: $TSPU_BLOCKED_CNT)"
    fi
}

test_single_category() {
    local cat_title="$1"
    local cat_file="$2"
    local cat_type="$3"
    local base_pct="$4"
    BEST_CAT_NAME=""; BEST_CAT_ARGS=""
    local best_s=-1; local best_t=-1; local idx=0
    local total_in_cat=$(wc -l < "$cat_file" 2>/dev/null | tr -d ' ')
    [ "${total_in_cat:-0}" -eq 0 ] && return

    log_ux "$base_pct" "STAGE" "═══ Категория: $cat_title ($total_in_cat) ═══"
    while IFS='|' read -r m_name m_args || [ -n "$m_name" ]; do
        [ -f "$STOP_FLAG" ] && break
        [ -z "$m_name" ] && continue
        idx=$((idx + 1))
        local full_strat=""
        case "$cat_type" in
            core) full_strat=$(assemble_combo_strategy "$m_args" "" "" "" "") ;;
            yt)   full_strat=$(assemble_combo_strategy "" "$m_args" "" "" "") ;;
            disc) full_strat=$(assemble_combo_strategy "" "" "$m_args" "" "") ;;
            gv)   full_strat=$(assemble_combo_strategy "" "" "" "" "$m_args") ;;
        esac
        log_ux "$base_pct" "STAGE" "▶ [$cat_title $idx/$total_in_cat]: $m_name"
        setup_isolated_channel "$full_strat"
        local pair=$(evaluate_domains_split "$SEC_DOMAINS" "$ZM_DOMAINS" "$base_pct")
        cleanup_sandbox
        local s_ok=$(echo "$pair" | cut -d: -f1)
        local z_ok=$(echo "$pair" | cut -d: -f2)
        local tot_ok=$((s_ok + z_ok))
        local diff_ctrl=$((tot_ok - CTRL_TOTAL_OK)); [ "$diff_ctrl" -ge 0 ] && diff_ctrl="+$diff_ctrl"
        if [ "$ZM_COUNT" -gt 0 ] && [ "$INCLUDE_ZM_DOMAINS" = "1" ]; then
            log_ux "$base_pct" "RESULT" "◼ [$m_name] ➔ Секции: $s_ok/$SEC_COUNT | ZM: $z_ok/$ZM_COUNT | Всего: $tot_ok/$DOM_COUNT ($diff_ctrl)"
        else
            log_ux "$base_pct" "RESULT" "◼ [$m_name] ➔ Домены секции: $s_ok/$SEC_COUNT ($diff_ctrl)"
        fi
        printf "%d|%d|%s|%s\n" "$s_ok" "$tot_ok" "$m_name" "$full_strat" >> "$RESULTS_FILE"
        if [ "$s_ok" -gt "$best_s" ] || { [ "$s_ok" -eq "$best_s" ] && [ "$tot_ok" -gt "$best_t" ]; }; then
            best_s="$s_ok"; best_t="$tot_ok"
            BEST_CAT_NAME="$m_name"; BEST_CAT_ARGS="$m_args"
        fi
        if [ "$s_ok" -gt "$GLOBAL_BEST_SEC" ] || { [ "$s_ok" -eq "$GLOBAL_BEST_SEC" ] && [ "$tot_ok" -gt "$GLOBAL_BEST_TOT" ]; }; then
            GLOBAL_BEST_SEC="$s_ok"; GLOBAL_BEST_TOT="$tot_ok"
            GLOBAL_BEST_NAME="$m_name"; GLOBAL_BEST_BODY="$full_strat"
        fi
    done < "$cat_file"
    [ -n "$BEST_CAT_NAME" ] && log_ux "$base_pct" "BEST" "★ Лучший в категории [$cat_title]: $BEST_CAT_NAME ($best_s/$SEC_COUNT)"
}

get_followers() {
    local src="$1"
    local out=""
    local _st _sn _fe _ff
    for _st in $(uci -q show forkop_zapret 2>/dev/null | sed -n 's/^forkop_zapret\.cfg_\([^.]*\)=section_settings$/\1/p'); do
        _fe=$(uci -q get "forkop_zapret.cfg_${_st}.follow_enabled" 2>/dev/null)
        _ff=$(uci -q get "forkop_zapret.cfg_${_st}.follow_from" 2>/dev/null)
        if [ "$_fe" = "1" ] && [ "$_ff" = "$src" ]; then
            _sn=$(uci -q get "forkop_zapret.cfg_${_st}.section_name" 2>/dev/null)
            [ -n "$_sn" ] && out="$out $_sn"
        fi
    done
    echo "$out"
}

atomic_apply_strategy() {
    local strat_name="$1"
    local strat_body="$2"
    local all_selected=$(echo "$3" | tr ',' ' ')
    local _orig_secs="$all_selected"
    for _sec in $_orig_secs; do
        for _f in $(get_followers "$_sec"); do
            case " $all_selected " in
                *" $_f "*) ;;
                *) all_selected="$all_selected $_f" ;;
            esac
        done
    done

    log_ux 95 "STAGE" "═══ ЭТАП 3: Применение стратегии [$strat_name] ═══"
    silence_standalone_zapret

    local zapret_secs=$(/bin/sh "$PARSER" --filter-zapret-sections "$all_selected")
    local applied_cnt=0

    local fk_conf="/etc/config/forkop"
    [ ! -f "$fk_conf" ] && [ -f "/etc/config/podkop" ] && fk_conf="/etc/config/podkop"
    if [ -f "$fk_conf" ]; then
        local pkg=$(basename "$fk_conf")
        for s in $all_selected; do
            [ -z "$s" ] && continue
            case " $zapret_secs " in
                *" $s "*)
                    local existing_opts=$(uci -q show "${pkg}.${s}" 2>/dev/null | grep -E '\.(zapret_strategy|zapret_args|nfqws_opt|desync_opt|strategy|zapret_options)=' | cut -d. -f3 | cut -d= -f1)
                    if [ -n "$existing_opts" ]; then
                        for opt in $existing_opts; do
                            uci -q set "${pkg}.${s}.${opt}=${strat_body}"
                        done
                    else
                        uci -q set "${pkg}.${s}.zapret_strategy=${strat_body}"
                    fi
                    applied_cnt=$((applied_cnt + 1))
                    log_ux 97 "INFO" "  ✓ Секция [$s] (Zapret) — стратегия записана."
                    ;;
                *)
                    log_ux 96 "WARN" "  🛡️ Секция [$s] (VPN/DNS) — только домены, настройки НЕ тронуты."
                    ;;
            esac
        done
        [ "$applied_cnt" -gt 0 ] && uci -q commit "$pkg"
    fi

    # per-section сохранение (для UI/cron по секциям)
    for s in $all_selected; do
        [ -z "$s" ] && continue
        case " $zapret_secs " in
            *" $s "*)
                local sec_key=$(echo "$s" | tr -c 'a-zA-Z0-9_' '_')
                uci -q set "forkop_zapret.sec_${sec_key}=section_strategy" 2>/dev/null
                uci -q set "forkop_zapret.sec_${sec_key}.section_name=${s}"
                uci -q set "forkop_zapret.sec_${sec_key}.best_strategy=${strat_name}"
                uci -q set "forkop_zapret.sec_${sec_key}.best_body=${strat_body}"
                ;;
        esac
    done
    uci -q commit forkop_zapret

    if [ -f "/etc/config/zapret" ]; then
        cp /etc/config/zapret /etc/config/zapret.bak
        local multiline_body=$(echo "$strat_body" | sed 's/[[:space:]]\+--/\n--/g')
        sed -i "/^[[:space:]]*option NFQWS_OPT '/,/^[[:space:]]*'[[:space:]]*\$/d" /etc/config/zapret
        {
            echo "	option NFQWS_OPT '"
            echo "#$strat_name"
            echo "$multiline_body"
            echo "'"
        } >> /etc/config/zapret
    fi

    uci -q set forkop_zapret.settings=main
    uci -q set forkop_zapret.settings.best_strategy="$strat_name"
    uci -q commit forkop_zapret

    if [ "$applied_cnt" -gt 0 ]; then
        if [ -x /etc/init.d/forkop ]; then
            /etc/init.d/forkop reload >/dev/null 2>&1 || /etc/init.d/forkop restart >/dev/null 2>&1
        fi
        silence_standalone_zapret
        log_ux 99 "BEST" "Стратегия [$strat_name] применена в $applied_cnt секциях Zapret."
    else
        log_ux 97 "WARN" "⚠️ Среди секций ($all_selected) нет Zapret-секций."
        log_ux 98 "COPY_HEAD" "📋 СТРАТЕГИЯ ДЛЯ РУЧНОЙ ВСТАВКИ:"
        log_ux 99 "COPY_BOX" "$strat_body"
    fi
}

run_main() {
    local sections="$1"
    local auto_apply="$2"
    local is_cron="$3"

    echo $$ > "$LOCK_FILE"
    rm -f "$STOP_FLAG"
    : > "$LOG_FILE"
    : > "$RESULTS_FILE"
    trap 'on_exit' EXIT INT TERM

    # Чистим возможные утечки от предыдущего упавшего прогона (критично для cron)
    cleanup_sandbox 2>/dev/null

    load_settings "$sections"
    if [ "$is_cron" = "1" ]; then
        log_ux 1 "STAGE" "═══ CRON-ПРОВЕРКА (Секции: $sections) ═══"
    else
        log_ux 1 "STAGE" "═══ МАСТЕР ПОДБОРА (Секции: $sections | Категории: $STRAT_CATS | All: $ALL_COMBOS) ═══"
    fi
    silence_standalone_zapret

    if [ ! -x "$NFQWS_BIN" ]; then
        log_ux 100 "ERR" "ОШИБКА: nfqws не найден."
        exit 1
    fi

    local raw_sec_domains=$(/bin/sh "$PARSER" --get-section-domains "$sections" | tr '\n' ' ')
    local raw_zm_domains=""
    if [ "$is_cron" != "1" ] && [ "$INCLUDE_ZM_DOMAINS" = "1" ]; then
        local all_domains=$(/bin/sh "$PARSER" --get-domains "$sections" | tr '\n' ' ')
        for d in $all_domains; do
            case " $raw_sec_domains " in
                *" $d "*) ;;
                *) raw_zm_domains="${raw_zm_domains:+$raw_zm_domains }$d" ;;
            esac
        done
    fi

    run_baseline_control_test "$raw_sec_domains" "$raw_zm_domains"

    SEC_DOMAINS="$VALID_SEC_DOMAINS"
    ZM_DOMAINS="$VALID_ZM_DOMAINS"
    SEC_COUNT=$(echo "$SEC_DOMAINS" | wc -w | tr -d ' ')
    ZM_COUNT=$(echo "$ZM_DOMAINS" | wc -w | tr -d ' ')
    DOM_COUNT=$((SEC_COUNT + ZM_COUNT))

    if [ "$DOM_COUNT" -eq 0 ]; then
        log_ux 100 "ERR" "ОШИБКА: все проверяемые домены исключены (DNS/IP-блок)."
        exit 1
    fi

    GLOBAL_BEST_SEC=-1; GLOBAL_BEST_TOT=-1
    GLOBAL_BEST_NAME=""; GLOBAL_BEST_BODY=""

    if [ "$is_cron" = "1" ]; then
        cron_express_verify_active_forkop "$SEC_DOMAINS" "$sections" && exit 0
        test_custom_strategy "$auto_apply" "$sections" && { log_ux 100 "BEST" "═══ ЗАВЕРШЕНО ═══"; exit 0; }
    else
        # 1) Текущая боевая стратегия секции (после контроля)
        manual_verify_current_active_strategy "$sections" && exit 0
        # 2) Кастомная стратегия пользователя
        test_custom_strategy "$auto_apply" "$sections" && { log_ux 100 "BEST" "═══ ЗАВЕРШЕНО ═══"; exit 0; }
    fi

    prepare_categorized_strategies

    # 3) Быстрый гибрид — если выбрано больше одной группы
    if [ "$is_cron" != "1" ]; then
        test_quick_hybrid "$sections" "$auto_apply" && { log_ux 100 "BEST" "═══ ЗАВЕРШЕНО ═══"; exit 0; }
    fi

    BEST_GEN_NAME=""; BEST_GEN_ARGS=""
    BEST_FTLS_NAME=""; BEST_FTLS_ARGS=""
    BEST_YT_NAME=""; BEST_YT_ARGS=""
    BEST_DISC_NAME=""; BEST_DISC_ARGS=""
    BEST_GV_NAME=""; BEST_GV_ARGS=""

    case ",$STRAT_CATS," in *,general,*)  test_single_category "General v1–v11" "$CAT_GENERAL" "core" 18; BEST_GEN_NAME="$BEST_CAT_NAME";  BEST_GEN_ARGS="$BEST_CAT_ARGS" ;; esac
    case ",$STRAT_CATS," in *,faketls,*)  test_single_category "FakeTLS"         "$CAT_FAKETLS" "core" 32; BEST_FTLS_NAME="$BEST_CAT_NAME"; BEST_FTLS_ARGS="$BEST_CAT_ARGS" ;; esac
    case ",$STRAT_CATS," in *,youtube,*)  test_single_category "YouTube"          "$CAT_YOUTUBE" "yt"   46; BEST_YT_NAME="$BEST_CAT_NAME";   BEST_YT_ARGS="$BEST_CAT_ARGS"   ;; esac
    case ",$STRAT_CATS," in *,discord,*)  test_single_category "Discord"          "$CAT_DISCORD" "disc" 60; BEST_DISC_NAME="$BEST_CAT_NAME"; BEST_DISC_ARGS="$BEST_CAT_ARGS" ;; esac
    case ",$STRAT_CATS," in *,gv,*)       test_single_category "Игровые"          "$CAT_GV"      "gv"   72; BEST_GV_NAME="$BEST_CAT_NAME";   BEST_GV_ARGS="$BEST_CAT_ARGS"   ;; esac

    : > "$STR_FILE"
    if [ "$ALL_COMBOS" = "1" ]; then
        log_ux 78 "STAGE" "═══ ЭТАП 2.2: Все комбинации ═══"
        local cores_file="$WORK_DIR/combo_cores.txt"; : > "$cores_file"
        case ",$STRAT_CATS," in *,general,*) cat "$CAT_GENERAL" >> "$cores_file" ;; esac
        case ",$STRAT_CATS," in *,faketls,*) cat "$CAT_FAKETLS" >> "$cores_file" ;; esac
        [ ! -s "$cores_file" ] && head -n 1 "$CAT_GENERAL" > "$cores_file"

        local yts_file="$WORK_DIR/combo_yts.txt"
        case ",$STRAT_CATS," in *,youtube,*) cp "$CAT_YOUTUBE" "$yts_file" ;; *) echo "DefaultYT|" > "$yts_file" ;; esac
        local discs_file="$WORK_DIR/combo_discs.txt"
        case ",$STRAT_CATS," in *,discord,*) cp "$CAT_DISCORD" "$discs_file" ;; *) head -n 1 "$CAT_DISCORD" > "$discs_file" ;; esac
        local gvs_file="$WORK_DIR/combo_gvs.txt"
        case ",$STRAT_CATS," in *,gv,*) cp "$CAT_GV" "$gvs_file" ;; *) head -n 1 "$CAT_GV" > "$gvs_file" ;; esac

        while IFS='|' read -r c_n c_a; do
            [ -z "$c_n" ] && continue
            while IFS='|' read -r y_n y_a; do
                [ -z "$y_n" ] && continue
                while IFS='|' read -r d_n d_a; do
                    [ -z "$d_n" ] && continue
                    while IFS='|' read -r g_n g_a; do
                        [ -z "$g_n" ] && continue
                        local cname="Combo_${c_n}+${y_n}+${d_n}+${g_n}"
                        local cbody=$(assemble_combo_strategy "$c_a" "$y_a" "$d_a" "" "$g_a")
                        printf "#%s\n%s\n" "$cname" "$cbody" >> "$STR_FILE"
                    done < "$gvs_file"
                done < "$discs_file"
            done < "$yts_file"
        done < "$cores_file"
    else
        log_ux 78 "STAGE" "═══ ЭТАП 2.2: Комбинации лучших найденных ═══"
        local c1=$(assemble_combo_strategy "$BEST_GEN_ARGS" "$BEST_YT_ARGS" "$BEST_DISC_ARGS" "" "$BEST_GV_ARGS")
        printf "#Combo_Best_General(%s)+YT(%s)+Disc(%s)\n%s\n" "${BEST_GEN_NAME:-Def}" "${BEST_YT_NAME:-Def}" "${BEST_DISC_NAME:-Def}" "$c1" >> "$STR_FILE"
        if [ -n "$BEST_FTLS_ARGS" ]; then
            local c2=$(assemble_combo_strategy "$BEST_FTLS_ARGS" "$BEST_YT_ARGS" "$BEST_DISC_ARGS" "" "$BEST_GV_ARGS")
            printf "#Combo_Best_FakeTLS(%s)+YT(%s)+Disc(%s)\n%s\n" "${BEST_FTLS_NAME}" "${BEST_YT_NAME:-Def}" "${BEST_DISC_NAME:-Def}" "$c2" >> "$STR_FILE"
        fi
    fi

    local single_best_sec="$GLOBAL_BEST_SEC"
    local single_best_tot="$GLOBAL_BEST_TOT"
    local single_best_name="$GLOBAL_BEST_NAME"
    local single_best_body="$GLOBAL_BEST_BODY"
    local combo_best_sec=0
    local combo_best_tot=0
    local combo_best_name=""
    local combo_best_body=""

    local combo_total=$(grep -c '^#' "$STR_FILE" 2>/dev/null)
    local combo_cur=0; local s_name=""; local s_body=""
    while IFS= read -r line || [ -n "$line" ]; do
        [ -f "$STOP_FLAG" ] && break
        case "$line" in
            \#*) s_name="${line#\#}" ;;
            --*)
                s_body="$line"
                combo_cur=$((combo_cur + 1))
                local pct=$(( 80 + (combo_cur * 12 / (combo_total > 0 ? combo_total : 1)) ))
                log_ux "$pct" "STAGE" "▶ Комбинация [$combo_cur/$combo_total]: $s_name"
                setup_isolated_channel "$s_body"
                local pair=$(evaluate_domains_split "$SEC_DOMAINS" "$ZM_DOMAINS" "$pct")
                cleanup_sandbox
                local s_ok=$(echo "$pair" | cut -d: -f1)
                local z_ok=$(echo "$pair" | cut -d: -f2)
                local tot_ok=$((s_ok + z_ok))
                local diff_ctrl=$((tot_ok - CTRL_TOTAL_OK)); [ "$diff_ctrl" -ge 0 ] && diff_ctrl="+$diff_ctrl"
                if [ "$ZM_COUNT" -gt 0 ] && [ "$INCLUDE_ZM_DOMAINS" = "1" ]; then
                    log_ux "$pct" "RESULT" "◼ КОМБО [$s_name] ➔ Секции: $s_ok/$SEC_COUNT | ZM: $z_ok/$ZM_COUNT | Всего: $tot_ok/$DOM_COUNT ($diff_ctrl)"
                else
                    log_ux "$pct" "RESULT" "◼ КОМБО [$s_name] ➔ Домены: $s_ok/$SEC_COUNT ($diff_ctrl)"
                fi
                printf "%d|%d|%s|%s\n" "$s_ok" "$tot_ok" "$s_name" "$s_body" >> "$RESULTS_FILE"
                if [ "$s_ok" -gt "$combo_best_sec" ] || { [ "$s_ok" -eq "$combo_best_sec" ] && [ "$tot_ok" -gt "$combo_best_tot" ]; }; then
                    combo_best_sec="$s_ok"; combo_best_tot="$tot_ok"
                    combo_best_name="$s_name"; combo_best_body="$s_body"
                fi
                ;;
        esac
    done < "$STR_FILE"

    # Комбинация приоритетнее одиночной при равенстве; перед применением — финальная проверка.
    local final_name="$single_best_name"
    local final_body="$single_best_body"
    local final_sec="$single_best_sec"
    local final_tot="$single_best_tot"
    if [ -n "$combo_best_name" ] && { [ "$combo_best_sec" -gt "$single_best_sec" ] || [ "$combo_best_sec" -eq "$single_best_sec" ]; }; then
        log_ux 96 "STAGE" "═══ ФИНАЛЬНАЯ ПРОВЕРКА КОМБИНАЦИИ [$combo_best_name] ═══"
        setup_isolated_channel "$combo_best_body"
        local vpair=$(evaluate_domains_split "$SEC_DOMAINS" "$ZM_DOMAINS" 96)
        cleanup_sandbox
        local v_ok=$(echo "$vpair" | cut -d: -f1)
        local v_zm=$(echo "$vpair" | cut -d: -f2)
        local v_tot=$((v_ok + v_zm))
        if [ "$v_ok" -ge "$combo_best_sec" ]; then
            final_name="$combo_best_name"; final_body="$combo_best_body"
            final_sec="$v_ok"; final_tot="$v_tot"
            log_ux 97 "BEST" "✓ Комбинация подтверждена: секции $v_ok/$SEC_COUNT, всего $v_tot/$DOM_COUNT"
        else
            log_ux 97 "WARN" "Комбинация просела ($v_ok/$SEC_COUNT) — применяю одиночную [$single_best_name]"
        fi
    fi
    GLOBAL_BEST_NAME="$final_name"
    GLOBAL_BEST_BODY="$final_body"
    GLOBAL_BEST_SEC="$final_sec"
    GLOBAL_BEST_TOT="$final_tot"

    if [ "$GLOBAL_BEST_TOT" -le 0 ] || [ -z "$GLOBAL_BEST_NAME" ]; then
        log_ux 100 "ERR" "Подбор завершён: ни одна стратегия не дала результата."
        exit 1
    fi

    local best_diff=$((GLOBAL_BEST_TOT - CTRL_TOTAL_OK)); [ "$best_diff" -ge 0 ] && best_diff="+$best_diff"
    uci -q set forkop_zapret.settings=main
    uci -q set forkop_zapret.settings.best_strategy="$GLOBAL_BEST_NAME"
    uci -q commit forkop_zapret

    log_ux 94 "BEST" "🏆 ПОБЕДИТЕЛЬ: [$GLOBAL_BEST_NAME] ➔ Секции: $GLOBAL_BEST_SEC/$SEC_COUNT | Всего: $GLOBAL_BEST_TOT/$DOM_COUNT ($best_diff)"

    if [ "$auto_apply" = "1" ]; then
        atomic_apply_strategy "$GLOBAL_BEST_NAME" "$GLOBAL_BEST_BODY" "$sections"
    else
        /etc/init.d/dnsmasq reload >/dev/null 2>&1
        log_ux 96 "COPY_HEAD" "📋 АВТОПОДСТАНОВКА ВЫКЛЮЧЕНА — СТРАТЕГИЯ:"
        log_ux 98 "COPY_BOX" "$GLOBAL_BEST_BODY"
    fi

    if [ -s "$RESULTS_FILE" ]; then
        log_ux 99 "STATS" "═══ СТАТИСТИКА ПО ПРОВЕРЕННЫМ СТРАТЕГИЯМ ═══"
        sort -t'|' -k1,1nr -k2,2nr "$RESULTS_FILE" 2>/dev/null | while IFS='|' read -r _a _b _c _d; do
            [ -n "$_c" ] && log_ux 99 "STATS" "  $(short_strategy_name "$_c") — секции $_a/$SEC_COUNT, всего $_b/$DOM_COUNT"
        done
        log_ux 99 "STATS" "🏆 Лучшая: $(short_strategy_name "$GLOBAL_BEST_NAME") ($GLOBAL_BEST_NAME)"
    fi

    log_ux 100 "BEST" "═══ ТЕСТИРОВАНИЕ ЗАВЕРШЕНО ═══"
}

case "$1" in
    --run)
        (
            echo $$ > "$LOCK_FILE"
            run_main "$2" "${3:-0}" "${4:-0}"
        ) </dev/null >/dev/null 2>&1 &
        ;;
    --stop)
        touch "$STOP_FLAG"
        if [ -f "$LOCK_FILE" ]; then
            MAIN_PID=$(cat "$LOCK_FILE" 2>/dev/null)
            [ -n "$MAIN_PID" ] && kill_pid_tree "$MAIN_PID"
        fi
        kill_matching "runner.sh --run"
        kill_matching "curl.*--resolve"
        cleanup_sandbox
        rm -f "$LOCK_FILE"
        log_ux 100 "WARN" "🛑 Тестирование остановлено. Процессы и песочница очищены."
        ;;
    --apply-custom)
        load_settings "$2"
        update_fake_bins
        atomic_apply_strategy "$3" "$4" "$2"
        ;;
    --status)
        if [ -f "$LOCK_FILE" ] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
            echo '{"running":true}'
        else
            echo '{"running":false}'
        fi
        ;;
    *)
        echo "Usage: $0 [--run 'sections' auto_apply is_cron | --stop | --apply-custom 'secs' 'name' 'body' | --status]"
        ;;
esac