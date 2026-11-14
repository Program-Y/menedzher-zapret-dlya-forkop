#!/bin/sh
# Файл: /usr/libexec/forkop-zapret/check.sh
# Проверка блокировки доменов секций:
#   --block  '<sections>'  — без стратегий (как с самого роутера)
#   --forkop '<sections>'  — через forkop (netns + veth к br-lan, как LAN-клиент)
#   --stop                 — убрать netns/процессы

PARSER="/usr/libexec/forkop-zapret/parser.sh"
WORK="/tmp/forkop_zapret"
LOG="$WORK/check.log"
LOCK="$WORK/check.lock"
DOMAINS_FILE="$WORK/check_domains.txt"
BEFORE_FILE="$WORK/check_before.txt"

SPEED_LIMIT_PAGE=3000
SPEED_TIME_PAGE=2
SPEED_LIMIT_JS=5000
SPEED_TIME_JS=2

NETNS="fzcheck"
NETNS_IP="192.168.2.250"
LAN_IF="br-lan"
LAN_GW="192.168.2.1"

mkdir -p "$WORK"

logc() {
    printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$1" >> "$LOG"
}

# --- резолв «настоящего» IP (DoH, мимо forkop) ---
resolve_real_ip() {
    local dom="$1" ip=""
    ip=$(curl -s -k -H "accept: application/dns-json" --connect-timeout 2 --max-time 4 \
        "https://8.8.8.8/resolve?name=${dom}&type=A" 2>/dev/null | \
        grep -oE '"data"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | \
        grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
        grep -vE '^(127\.|0\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|198\.1[89]\.)' | head -n1)
    if [ -z "$ip" ]; then
        ip=$(nslookup "$dom" 8.8.8.8 2>/dev/null | tail -n +3 | \
            grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
            grep -vE '^(127\.|0\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|198\.1[89]\.)' | head -n1)
    fi
    echo "$ip"
}

# --- резолв как у LAN-клиента (через роутер/ forkop DNS, может вернуть fake-IP) ---
resolve_lan_ip() {
    nslookup "$1" "$LAN_GW" 2>/dev/null | tail -n +3 | \
        grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
        grep -v "^${LAN_GW}$" | head -n1
}

# --- глубокая проверка: HTML + ключевые JS/CSS, детект заморозки/обрезки ---
deep_check() {
    local dom="$1" ip="$2" prefix="$3"
    local tmp="$WORK/chk_${dom}.$$"
    local out rc code tconn size
    out=$($prefix curl -s --resolve "${dom}:443:${ip}" \
        --connect-timeout 3 --max-time 5 \
        --speed-limit "$SPEED_LIMIT_PAGE" --speed-time "$SPEED_TIME_PAGE" \
        -H "Accept: text/html,application/xhtml+xml,*/*;q=0.8" \
        -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0" \
        -w "%{http_code}|%{time_connect}|%{size_download}" -o "$tmp" "https://${dom}/" 2>/dev/null)
    rc=$?
    code=$(echo "$out" | cut -d'|' -f1)
    tconn=$(echo "$out" | cut -d'|' -f2)
    size=$(echo "$out" | cut -d'|' -f3)
    [ "$rc" -eq 28 ] && { rm -f "$tmp"; echo "FREEZE"; return; }
    if [ "$rc" -ne 0 ] || [ "$code" = "000" ] || [ -z "$code" ]; then rm -f "$tmp"; echo "FAIL"; return; fi
    case "$code" in 403|451) rm -f "$tmp"; echo "FREEZE"; return ;; esac

    local sub_js="" sub_css=""
    if [ -s "$tmp" ]; then
        sub_js=$(grep -oE 'src="[^"]+\.js[^"]*"' "$tmp" 2>/dev/null | head -n1 | sed 's/^src="//; s/"$//')
        sub_css=$(grep -oE 'href="[^"]+\.css[^"]*"' "$tmp" 2>/dev/null | head -n1 | sed 's/^href="//; s/"$//')
    fi
    rm -f "$tmp"

    local s u
    for s in "${sub_js:-}" "${sub_css:-}"; do
        [ -z "$s" ] && continue
        case "$s" in
            https://*|http://*) u="$s" ;;
            //*) u="https:$s" ;;
            /*)  u="https://${dom}${s}" ;;
            *)   u="https://${dom}/${s}" ;;
        esac
        case "$u" in
            "https://${dom}/"*) ;;
            *) continue ;;
        esac
        local hdr="$WORK/hdr_${dom}.$$"
        local so src rc2 code2 sz2 clen
        so=$($prefix curl -s --resolve "${dom}:443:${ip}" \
            --connect-timeout 3 --max-time 6 \
            --speed-limit "$SPEED_LIMIT_JS" --speed-time "$SPEED_TIME_JS" \
            -A "Mozilla/5.0" -D "$hdr" -w "%{http_code}|%{size_download}" -o /dev/null "$u" 2>/dev/null)
        rc2=$?
        code2=$(echo "$so" | cut -d'|' -f1)
        sz2=$(echo "$so" | cut -d'|' -f2)
        clen=$(awk 'tolower($1)=="content-length:"{v=$2} END{print v}' "$hdr" 2>/dev/null | tr -d '\r')
        rm -f "$hdr"
        [ "$rc2" -eq 28 ] && { echo "FREEZE"; return; }
        if [ "$rc2" -ne 0 ] || [ "$code2" = "000" ] || [ -z "$code2" ]; then echo "FREEZE"; return; fi
        case "$code2" in 403|451|5*) echo "FREEZE"; return ;; esac
        if [ -n "$clen" ] && [ "${sz2:-0}" -lt "$clen" ]; then echo "FREEZE"; return; fi
        if [ "${sz2:-0}" -lt 500 ]; then echo "FREEZE"; return; fi
    done
    echo "OK"
}

# --- классификация без стратегии ---
classify_block() {
    local dom="$1"
    local ip=$(resolve_real_ip "$dom")
    [ -z "$ip" ] && { echo "DNS_FAIL||||"; return; }
    local st=$(deep_check "$dom" "$ip" "")
    if [ "$st" = "OK" ]; then echo "OK|$ip|||"; return; fi
    # проверим, жив ли IP с белым SNI
    local sni=$(curl -sI -k --resolve "ya.ru:443:${ip}" --connect-timeout 2 --max-time 3 \
        -w "%{http_code}|%{time_connect}" -o /dev/null "https://ya.ru/" 2>/dev/null)
    local stc=$(echo "$sni" | cut -d'|' -f2)
    case "$stc" in
        0|0.000*|0,000*|"") echo "IP_BLOCK|$ip|||" ;;
        *)                  echo "DPI_BLOCK|$ip|||" ;;
    esac
}

# --- git netns ---
setup_netns() {
    ip netns del "$NETNS" 2>/dev/null
    ip link del "fzchk1" 2>/dev/null
    ip netns add "$NETNS" 2>/dev/null || return 1
    ip link add fzchk0 type veth peer name fzchk1 2>/dev/null || { ip netns del "$NETNS" 2>/dev/null; return 1; }
    ip link set fzchk0 netns "$NETNS"
    ip link set fzchk1 master "$LAN_IF" up
    ip netns exec "$NETNS" ip link set lo up
    ip netns exec "$NETNS" ip link set fzchk0 up
    ip netns exec "$NETNS" ip addr add "${NETNS_IP}/24" dev fzchk0
    ip netns exec "$NETNS" ip route add default via "$LAN_GW"
    return 0
}

cleanup_netns() {
    ip netns del "$NETNS" 2>/dev/null
    ip link del fzchk1 2>/dev/null
}

# --- список доменов секций (без ZM) ---
collect_domains() {
    local sections="$1"
    local sec
    for sec in $(echo "$sections" | tr ',' ' '); do
        [ -z "$sec" ] && continue
        /bin/sh "$PARSER" --get-section-domains "$sec" 2>/dev/null
    done | awk '!seen[$0]++'
}

do_block() {
    local sections="$1" onlydom="$2"
    : > "$LOG"
    : > "$BEFORE_FILE"
    local doms
    if [ -n "$onlydom" ]; then
        doms="$onlydom"
    else
        doms=$(collect_domains "$sections")
    fi
    [ -z "$doms" ] && { logc "[ERR] Нет доменов в выбранных секциях"; logc "[DONE] block"; return; }
    echo "$doms" > "$DOMAINS_FILE"
    local total=$(echo "$doms" | wc -w | tr -d ' ')
    logc "[INFO] Проверка блокировки: $total доменов (без ZM)"
    local i=0 dom res st ip
    for dom in $doms; do
        i=$((i + 1))
        res=$(classify_block "$dom")
        st=$(echo "$res" | cut -d'|' -f1)
        ip=$(echo "$res" | cut -d'|' -f2)
        echo "${dom}|${st}|${ip}" >> "$BEFORE_FILE"
        case "$st" in
            OK)        logc "[BLOCK_OK]  ✅ $dom — Домен доступен ($ip)" ;;
            DNS_FAIL)  logc "[BLOCK_DNS] ❔ $dom — Домена нет в DNS" ;;
            IP_BLOCK)  logc "[BLOCK_IP]  🚫 $dom — Заблокирован по IP ($ip)" ;;
            DPI_BLOCK) logc "[BLOCK_DPI] 🧊 $dom — Заблокирован по DPI ($ip)" ;;
        esac
    done
    logc "[DONE] block"
}

do_forkop() {
    local sections="$1" onlydom="$2"
    : > "$LOG"
    local doms
    if [ -n "$onlydom" ]; then
        doms="$onlydom"
    elif [ -s "$DOMAINS_FILE" ]; then
        doms=$(cat "$DOMAINS_FILE")
    else
        doms=$(collect_domains "$sections")
        echo "$doms" > "$DOMAINS_FILE"
    fi
    [ -z "$doms" ] && { logc "[ERR] Нет доменов"; logc "[DONE] forkop"; return; }
    if ! setup_netns; then
        logc "[ERR] Не удалось создать netns/veth (нужен kmod-veth)"
        logc "[DONE] forkop"
        return
    fi
    logc "[INFO] Проверка через forkop (netns $NETNS, ${NETNS_IP})"
    local total=$(echo "$doms" | wc -w | tr -d ' ')
    local i=0 dom ip st before bst
    for dom in $doms; do
        i=$((i + 1))
        ip=$(resolve_lan_ip "$dom")
        if [ -z "$ip" ]; then
            logc "[FORKOP_DNS] ❔ $dom — нет в DNS через роутер"
            continue
        fi
        st=$(deep_check "$dom" "$ip" "ip netns exec $NETNS")
        bst=""
        if [ -s "$BEFORE_FILE" ]; then
            bst=$(awk -F'|' -v d="$dom" '$1 == d {print $2; exit}' "$BEFORE_FILE")
        fi
        case "$st" in
            OK)    [ "$bst" = "OK" ] && b1="✅" || b1="❌"; logc "[FORKOP_OK]   ${b1}→✅ $dom — через forkop доступен" ;;
            FREEZE) [ "$bst" = "OK" ] && b1="✅" || b1="❌"; logc "[FORKOP_FAIL] ${b1}→🧊 $dom — через forkop заморозка/DPI" ;;
            *)     [ "$bst" = "OK" ] && b1="✅" || b1="❌"; logc "[FORKOP_FAIL] ${b1}→❌ $dom — через forkop недоступен" ;;
        esac
    done
    cleanup_netns
    logc "[DONE] forkop"
}

stop_previous() {
    ps 2>/dev/null | grep 'check.sh' | grep -v grep | awk -v me="$$" '$1 != me {print $1}' | xargs -r kill -9
    ip netns del fzcheck 2>/dev/null
    ip link del fzchk1 2>/dev/null
    rm -f "$LOCK"
}

case "$1" in
    --block)
        stop_previous
        echo $$ > "$LOCK"
        do_block "$2" "$3"
        rm -f "$LOCK"
        ;;
    --forkop)
        stop_previous
        echo $$ > "$LOCK"
        do_forkop "$2" "$3"
        rm -f "$LOCK"
        ;;
    --stop)
        cleanup_netns
        ps | grep 'check.sh' | grep -v grep | awk '{print $1}' | xargs -r kill -9
        rm -f "$LOCK"
        logc "[WARN] Проверка остановлена"
        ;;
    *)
        echo "Usage: $0 --block 'sections' | --forkop 'sections' | --stop"
        ;;
esac
