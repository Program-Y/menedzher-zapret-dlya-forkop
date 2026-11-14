#!/bin/sh
# Файл: /usr/libexec/forkop-zapret/parser.sh

FORKOP_CONF="/etc/config/forkop"
[ ! -f "$FORKOP_CONF" ] && [ -f "/etc/config/podkop" ] && FORKOP_CONF="/etc/config/podkop"
PKG_NAME=$(basename "$FORKOP_CONF")

RAW_DPI_URL="https://raw.githubusercontent.com/hyperion-cs/dpi-checkers/refs/heads/main/ru/tcp-16-20/suite.v2.json"

ZM_BASE_DOMAINS="ntc.party instagram.com facebook.com rutor.info rutracker.org epidemz.net.co nnmclub.to openwrt.org discord.com x.com filmix.my forum.ru-board.com play.google.com anitokyo.tv cub.red downloads.openwrt.org raw.githubusercontent.com youtu.be youtube.com i.ytimg.com i9.ytimg.com yt3.ggpht.com googleapis.com jnn-pa.googleapis.com googleusercontent.com signaler-pa.youtube.com youtubei.googleapis.com manifest.googlevideo.com rr4---sn-4g5e6nze.googlevideo.com rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com rr1---sn-ug5onuxaxjvh-n8v6.googlevideo.com"

resolve_community_list() {
    case "$1" in
        youtube)        echo "youtube.com youtu.be i.ytimg.com manifest.googlevideo.com" ;;
        discord)        echo "discord.com discord.gg gateway.discord.gg cdn.discordapp.com discord.media" ;;
        meta)           echo "instagram.com facebook.com static.cdninstagram.com" ;;
        twitter)        echo "x.com twitter.com t.co" ;;
        telegram)       echo "web.telegram.org core.telegram.org t.me" ;;
        cloudflare)     echo "cloudflare.com cdnjs.cloudflare.com" ;;
        google_ai)      echo "gemini.google.com aistudio.google.com notebooklm.google.com" ;;
        google_play)    echo "play.google.com gvt1.com play-lh.googleusercontent.com" ;;
        news)           echo "meduza.io bbc.com dw.com" ;;
        anime)          echo "shikimori.one jut.su animego.org" ;;
        hdrezka)        echo "rezka.ag hdrezka.ag" ;;
        tiktok)         echo "tiktok.com www.tiktok.com" ;;
        roblox)         echo "roblox.com www.roblox.com tr.rbxcdn.com" ;;
        geoblock)       echo "chatgpt.com claude.ai" ;;
        russia_inside)  echo "rutracker.org rutor.info ntc.party" ;;
        block|porn)     echo "rutracker.org rutor.info ntc.party" ;;
    esac
}

# --- Кэш и извлечение доменов из rule-set (.srs / .json) ---
RS_CACHE="/tmp/forkop_zapret/rs"
mkdir -p "$RS_CACHE" 2>/dev/null

community_url() {
    case "$1" in
        ads_hagezi_pro) echo "https://github.com/zxc-rv/ad-filter/releases/latest/download/adlist.srs" ;;
        supercell)      echo "https://raw.githubusercontent.com/ushan0v/sing-box-supercell-ruleset/main/supercell.srs" ;;
        github)         echo "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/github.srs" ;;
        *)              echo "https://github.com/itdoginfo/allow-domains/releases/latest/download/$1.srs" ;;
    esac
}

extract_rs_domains() {
    local ref="$1"
    [ -z "$ref" ] && return 0
    local base=$(basename "$ref" | sed 's/[?#].*$//')
    [ -z "$base" ] && base="ruleset"
    local file="" cand="$RS_CACHE/$base"
    if [ -f "$ref" ]; then
        file="$ref"
    elif [ -f "/etc/forkop/$base" ]; then
        file="/etc/forkop/$base"
    elif [ -f "$cand" ]; then
        file="$cand"
    else
        curl -fsSL --connect-timeout 5 --max-time 12 "$ref" -o "$cand" 2>/dev/null && [ -s "$cand" ] && file="$cand"
    fi
    [ -z "$file" ] && return 0
    local cache="$RS_CACHE/${base}.domains"
    if [ -s "$cache" ]; then
        cat "$cache"
        return 0
    fi
    local json="$RS_CACHE/${base}.json"
    if head -c 1 "$file" 2>/dev/null | grep -q '{'; then
        json="$file"
    else
        sing-box rule-set decompile "$file" -o "$json" 2>/dev/null || return 0
    fi
    jsonfilter -i "$json" -e '@.rules[*].domain[*]' -e '@.rules[*].domain_suffix[*]' 2>/dev/null | \
        sed 's/^"//; s/"$//' | grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' | awk '!seen[$0]++' > "$cache"
    [ "$json" != "$file" ] && rm -f "$json"
    cat "$cache"
}

# Универсальная очистка строки от мусора (CR, TAB, пробелы, кавычки)
_fz_clean() {
    printf '%s' "$1" | tr -d '\r\t' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[\047"]//g'
}

# Возвращает имена ВСЕХ реальных секций Forkop.
# Приоритет: uci show (корректно обрабатывает анонимные -> cfgXXXXXX)
get_all_section_names() {
    local secs=""

    if [ -f "$FORKOP_CONF" ] && command -v uci >/dev/null 2>&1; then
        secs=$(uci -q show "$PKG_NAME" 2>/dev/null | \
            sed -n "s/^${PKG_NAME}\.\([^.]*\)=.*/\1/p" | \
            tr -d '\r\t' | \
            sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[\047"]//g' | \
            grep -v -x -E 'settings|main|global|diagnostics' | \
            grep -v -E '^@')
    fi

    if [ -z "$secs" ] && [ -f "$FORKOP_CONF" ]; then
        secs=$(tr -d '\r' < "$FORKOP_CONF" | awk '
            function clean(s) { gsub(/[\047" \t]/, "", s); return s }
            $1 == "config" {
                if (NF >= 3 && $2 == "section") {
                    n = clean($3)
                    if (n != "" && n != "settings" && n != "main" && n != "global" && n != "diagnostics") print n
                }
                else if (NF == 2 && $2 !~ /^(section|settings|main|global|diagnostics)$/) {
                    n = clean($2)
                    if (n != "" && n !~ /^@/) print n
                }
            }
        ')
    fi

    echo "$secs" | sed '/^$/d'
}

# Является ли секция zapret-секцией.
is_zapret_section() {
    local s="$1"
    [ -z "$s" ] && return 1
    s=$(_fz_clean "$s")
    [ -z "$s" ] && return 1

    local action ctype mode
    action=$(uci -q get "${PKG_NAME}.${s}.action" 2>/dev/null | tr -d '\r\t"')
    ctype=$(uci -q get "${PKG_NAME}.${s}.connection_type" 2>/dev/null | tr -d '\r\t"')
    mode=$(uci -q get "${PKG_NAME}.${s}.mode" 2>/dev/null | tr -d '\r\t"')

    case "$action $ctype $mode" in
        *zapret*|*desync*|*nfqws*|*dpi*) return 0 ;;
    esac

    if uci -q show "${PKG_NAME}.${s}" 2>/dev/null | grep -qE '\.(zapret_strategy|zapret_args|nfqws_opt|desync_opt|zapret_options|zapret_enabled)='; then
        return 0
    fi

    return 1
}

# ИСПРАВЛЕНО: извлекаем домены через uci get, а не парсим файл awk-ом.
# uci корректно склеивает многострочные option domain (Forkop хранит их как
# многострочное значение), а awk по файлу терял все строки, кроме первой.
get_section_domains() {
    local target_sections
    target_sections=$(echo "$1" | tr ',' ' ')
    local tmp_dom="/tmp/fz_sec_domains.$$"
    : > "$tmp_dom"

    local sec
    for sec in $target_sections; do
        sec=$(_fz_clean "$sec")
        [ -z "$sec" ] && continue

        # 1) option domain   (одна многострочная строка в uci get)
        uci -q get "${PKG_NAME}.${sec}.domain" 2>/dev/null | tr -d '\r' >> "$tmp_dom"

        # 2) option/list custom_domains
        uci -q get "${PKG_NAME}.${sec}.custom_domains" 2>/dev/null | tr -d '\r' >> "$tmp_dom"

        # 3) option/list user_domains
        uci -q get "${PKG_NAME}.${sec}.user_domains" 2>/dev/null | tr -d '\r' >> "$tmp_dom"

        # 4) option/list domains
        uci -q get "${PKG_NAME}.${sec}.domains" 2>/dev/null | tr -d '\r' >> "$tmp_dom"

        # 5) option domain_suffix (на случай другого нейминга в Forkop)
        uci -q get "${PKG_NAME}.${sec}.domain_suffix" 2>/dev/null | tr -d '\r' >> "$tmp_dom"

        # 6) option domain_keyword
        uci -q get "${PKG_NAME}.${sec}.domain_keyword" 2>/dev/null | tr -d '\r' >> "$tmp_dom"

        # 7) файлы со списками доменов
        local dfile
        dfile=$(uci -q get "${PKG_NAME}.${sec}.user_domain_list_filepath" 2>/dev/null | tr -d '\r\t"')
        [ -z "$dfile" ] && dfile=$(uci -q get "${PKG_NAME}.${sec}.custom_domains_list_filepath" 2>/dev/null | tr -d '\r\t"')
        if [ -n "$dfile" ] && [ -f "$dfile" ]; then
            grep -vE '^[[:space:]]*(#|$)' "$dfile" | awk '{print $1}' >> "$tmp_dom"
        fi

        # 8) community_lists -> встроенные списки (srs)
        local clist _tmp_rs
        for clist in $(uci -q get "${PKG_NAME}.${sec}.community_lists" 2>/dev/null | tr -d '\r"'); do
            _tmp_rs="$RS_CACHE/.tmp_${clist}.$$"
            extract_rs_domains "$(community_url "$clist")" > "$_tmp_rs"
            if [ -s "$_tmp_rs" ]; then
                cat "$_tmp_rs" >> "$tmp_dom"
            else
                for cd in $(resolve_community_list "$clist"); do
                    echo "$cd" >> "$tmp_dom"
                done
            fi
            rm -f "$_tmp_rs"
        done

        # 9) rule_set / rule_set_with_subnets -> URL или локальный файл
        local rsref
        for rsref in $(uci -q get "${PKG_NAME}.${sec}.rule_set" 2>/dev/null | tr -d '\r"') \
                      $(uci -q get "${PKG_NAME}.${sec}.rule_set_with_subnets" 2>/dev/null | tr -d '\r"'); do
            [ -z "$rsref" ] && continue
            extract_rs_domains "$rsref" >> "$tmp_dom"
        done
    done

    # Нормализация: убираем "keyword:", "regexp:", "geosite:", оставляем только FQDN.
    # "keyword:wardogs" и "keyword:bulkhead" не являются доменами — отбрасываем.
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[\047"]//g; s/\r//g' "$tmp_dom" | \
        grep -vE '^(keyword:|regexp:|geosite:|ext:|option |list |#|$)' | \
        sed -E 's/^(full:|domain:|\+\.|\*\.)//g; s#^https?://##; s#/.*##; s/[[:space:]]+//g' | \
        grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' | \
        awk '!seen[$0]++'

    rm -f "$tmp_dom"
}

get_domains() {
    local tmp_all="/tmp/fz_all_domains.$$"
    : > "$tmp_all"

    get_section_domains "$1" >> "$tmp_all"

    for d in $ZM_BASE_DOMAINS; do
        echo "$d" >> "$tmp_all"
    done

    local dpi_cache="/tmp/forkop_zapret_dpi_suite.txt"
    if [ ! -s "$dpi_cache" ]; then
        curl -fsSL --connect-timeout 2 --max-time 4 "$RAW_DPI_URL" 2>/dev/null | \
            sed -n 's/.*"host":[[:space:]]*"\([^"]*\)".*/\1/p' | \
            sed -E 's#^https?://##; s#/.*##' | \
            grep -vE '\.ru$' > "$dpi_cache"
    fi
    [ -s "$dpi_cache" ] && grep -vE '\.ru$' "$dpi_cache" | head -n 25 >> "$tmp_all"

    grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' "$tmp_all" | awk '!seen[$0]++'
    rm -f "$tmp_all"
}

list_sections() {
    local secs
    secs=$(get_all_section_names)

    printf '{"sections":['
    local first=1
    local s
    for s in $secs; do
        s=$(_fz_clean "$s")
        [ -z "$s" ] && continue

        local ctype lists d_cnt is_z
        ctype=$(uci -q get "${PKG_NAME}.${s}.connection_type" 2>/dev/null | tr -d '\r\t"')
        [ -z "$ctype" ] && ctype=$(uci -q get "${PKG_NAME}.${s}.action" 2>/dev/null | tr -d '\r\t"')
        lists=$(uci -q get "${PKG_NAME}.${s}.community_lists" 2>/dev/null | tr -d '\r\t"')
        d_cnt=$(get_section_domains "$s" 2>/dev/null | wc -l | tr -d ' \r\t')
        [ -z "$d_cnt" ] && d_cnt=0
        is_z="false"
        if is_zapret_section "$s"; then is_z="true"; fi

        if [ -z "$lists" ]; then
            [ "$d_cnt" -gt 0 ] && lists="доменов: $d_cnt" || lists="список"
        else
            [ "$d_cnt" -gt 0 ] && lists="$lists (дом: $d_cnt)"
        fi

        [ "$first" -eq 0 ] && printf ','
        printf '{"id":"%s","type":"%s","is_zapret":%s,"lists":"%s"}' \
            "$s" "${ctype:-unknown}" "$is_z" "$lists"
        first=0
    done
    printf ']}\n'
}

filter_zapret_sections() {
    local target_sections out sec
    target_sections=$(echo "$1" | tr ',' ' ')
    out=""
    for sec in $target_sections; do
        sec=$(_fz_clean "$sec")
        [ -z "$sec" ] && continue
        if is_zapret_section "$sec"; then
            out="${out:+$out }$sec"
        fi
    done
    echo "$out"
}

case "$1" in
    --list-sections)          list_sections ;;
    --get-section-domains)    get_section_domains "$2" ;;
    --get-domains)            get_domains "$2" ;;
    --filter-zapret-sections) filter_zapret_sections "$2" ;;
    *) echo "Usage: $0 [--list-sections | --get-section-domains 's' | --get-domains 's' | --filter-zapret-sections 's']" ;;
esac