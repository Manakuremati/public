#!/bin/ash

# ddns script for OpenWrt running directly with ash.
# packets needed: curl, jq
# this script is made for cloudflare and it's API

# dynamic values –‑ edit the lines below if needed
CLOUDFLARE_TOKEN="YOUR_API_TOKEN"
ZONE_ID="YOUR_ZONE_ID"
RECORD_ID="YOUR_RECORD_ID"
RECORD_NAME="YOUR_DNS_NAME"
WAN_IFACE="YOUR_WAN_INTERFACE"
TTL=60
PROXIED=false


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

CURRENT_IP=$(ifstatus "$WAN_IFACE" | jsonfilter -e '@["ipv4-address"][0].address')

if [ -z "$CURRENT_IP" ]; then
    log notice "Unable to read IPv4 address from interface $WAN_IFACE"
    exit 1
fi

REMOTE_IP=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
    -H "Authorization: Bearer ${CLOUDFLARE_TOKEN}" \
    -H "Content-Type: application/json" |
    jq -r '.result.content')

if [ -z "$REMOTE_IP" ]; then
    log warning "Failed to retrieve current DNS value from cloudflare"
    exit 1
fi

if [ "$CURRENT_IP" = "$REMOTE_IP" ]; then
    log info "No change – ${RECORD_NAME} already points to ${CURRENT_IP}"
    exit 0
fi

PAYLOAD=$(printf '{"type":"A","name":"%s","content":"%s","ttl":%d,"proxied":%s}' \
    "${RECORD_NAME}" "${CURRENT_IP}" "${TTL}" "${PROXIED}")

RESP=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
    -H "Authorization: Bearer ${CLOUDFLARE_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "${PAYLOAD}")

if echo "$RESP" | jq -e '.success' >/dev/null; then
    log notice "Updated ${RECORD_NAME}: ${REMOTE_IP} → ${CURRENT_IP}"
else
    ERR=$(echo "$RESP" | jq -r '.errors[]?.message')
    log err "Failed to update DNS record: ${ERR:-unknown error}"
    exit 1
fi
