#!/bin/ash
set -eu

# wireguard watchdog script for OpenWrt
# packets needed: curl, jq
# this script resolves stale peers of given wireguard interfaces directly via cloudflare API
# by doing so it always gets the most up to date records, which are provided by the separate ddns.sh script
# if the cloudflare API is unavailable normal DNS will be used

# dynamic values -- edit the lines below if needed
INTERFACE_MAP="
wg01 wg01.example.com
wg02 wg02.example.com
"

DOH_URL="https://cloudflare-dns.com/dns-query"
DNS_TYPE="A"
HANDSHAKE_MAX_AGE=180
CF_API_TOKEN=""
CF_ZONE_ID=""


log() {
    case "$1" in
        emerg|alert|crit|err|warning|notice|info|debug)
            lvl=$1
            shift
            ;;
        *)
            lvl="notice"
            ;;
    esac

    msg="$*"
    logger -p "user.$lvl" "$msg"
}

lookup_via_doh() {
    hostname=$1
    doh_resp=$(curl -s -G \
        --max-time 5 \
        --data-urlencode "name=${hostname}" \
        --data-urlencode "type=${DNS_TYPE}" \
        -H "Accept: application/dns-json" \
        -H "Cache-Control: no-cache" \
        "${DOH_URL}")

    ip=$(echo "$doh_resp" |
        jq -r '.Answer[] | select(.type == 1) | .data' |
        head -n1 || true)

    if [ -n "$ip" ]; then
        log notice "Resolved $hostname → $ip via DoH"
        echo "$ip"
    else
        log warning "DoH lookup failed for $hostname"
        echo ""
    fi
}

resolve_via_cf() {
    hostname=$1

    if [ "$USE_API" -eq 0 ]; then
        lookup_via_doh "$hostname"
        return
    fi

    api_resp=$(curl -s -G \
        --max-time 5 \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data-urlencode "type=${DNS_TYPE}" \
        --data-urlencode "name=${hostname}" \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records")

    api_success=$(echo "$api_resp" | jq -r '.success // false')
    if [ "$api_success" = "true" ]; then
        ip=$(echo "$api_resp" | jq -r '.result[0].content // empty')
        if [ -n "$ip" ]; then
            log notice "Resolved $hostname → $ip via API"
            echo "$ip"
            return
        fi
        log warning "API lookup succeeded for $hostname but no ${DNS_TYPE} record found"
    else
        err_msg=$(echo "$api_resp" | jq -r '.errors[0].message // "unknown error"')
        log err "API lookup failed for $hostname: $err_msg"
    fi

    lookup_via_doh "$hostname"
}

if [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ZONE_ID" ]; then
    USE_API=1
else
    USE_API=0
    log notice "API credentials missing – all lookups will use DoH"
fi

[ -z "$(echo "$INTERFACE_MAP" | tr -d '[:space:]')" ] && exit 0

printf '%s\n' "$INTERFACE_MAP" | while IFS= read -r line; do
    line=$(printf '%s' "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$line" ] && continue

    iface=$(printf '%s' "$line" | awk '{print $1}')
    dnsname=$(printf '%s' "$line" | awk '{print $2}')

    if ! wg show "$iface" >/dev/null 2>&1; then
        log notice "Interface [$iface] not found – skipping"
        continue
    fi

    resolved_ip=""

    wg show "$iface" dump | while IFS=$'\t' read -r pubkey _ endpoint _ latest_hs _ _ keepalive; do
        [ -z "$pubkey" ] && continue
        [ -z "$keepalive" ] && continue
        [ "$keepalive" -eq 0 ] && continue

        stale=0
        if [ -z "$latest_hs" ] || [ "$latest_hs" -eq 0 ]; then
            stale=1
            log notice "[$iface] peer $pubkey never shook hands"
        else
            now=$(date +%s)
            age=$(( now - latest_hs ))
            if [ "$age" -gt "$HANDSHAKE_MAX_AGE" ]; then
                stale=1
                log notice "[$iface] peer $pubkey shook hands $age seconds ago → stale"
            fi
        fi
        if [ "$stale" -eq 0 ]; then
	    log info "[$iface] not stale → continue"
	continue
	fi

        if [ -z "$resolved_ip" ]; then
            resolved_ip=$(resolve_via_cf "$dnsname")
            if [ -z "$resolved_ip" ]; then
                log warning "[$iface] DNS lookup failed for $dnsname – cannot update peers"
                break
            fi
        fi

        ep_host=${endpoint%%:*}
        ep_port=${endpoint##*:}

        case "$ep_host" in
            *:*|*[!0-9.]*)
                current_ip=$(resolve_via_cf "$ep_host")
                ;;
            *)
                current_ip="$ep_host"
                ;;
        esac

        if [ -z "$current_ip" ]; then
            log warning "[$iface] peer $pubkey – cannot determine current IP (endpoint=$endpoint)"
            continue
        fi

        if [ "$ep_host" != "$resolved_ip" ]; then
            new_endpoint="${resolved_ip}:${ep_port}"
            if wg set "$iface" peer "$pubkey" endpoint "$new_endpoint"; then
                log notice "[$iface] peer $pubkey – endpoint updated from $endpoint to $new_endpoint (keepalive=${keepalive})"
            else
                log error "[$iface] peer $pubkey – FAILED to update endpoint"
            fi
        fi
    done
done
