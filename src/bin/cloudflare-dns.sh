#!/usr/bin/env bash
# Reconcile the internet-facing Cloudflare records for tecronin.uk.
# Anything not listed stays on the DNS-only "*" wildcard, resolves to the WAN IP,
# and is dropped by the firewall's Cloudflare-ranges source alias.
#
# Token: CF_API_TOKEN with Zone:DNS:Edit, Zone Settings:Edit, and (once origin
# pulls are folded in) SSL and Certificates:Edit. Separate from the DNS-01
# token in Traefik's .env. Export only when running this script.
#
# Not in this script (GUI, set-once): Security > WAF > Rate limiting rules,
# expression
#   (http.host eq "wiki.tecronin.uk" and http.request.uri.path eq "/login"
#    and http.request.method eq "POST")
# 10 requests / 10 seconds / IP, action Block.
set -euo pipefail

ZONE_NAME=tecronin.uk
: "${CF_API_TOKEN:?token needs Zone:DNS:Edit and Zone Settings:Edit}"

# The apex A record is not listed: OPNsense Dynamic DNS owns it. These CNAME to it.
# name     type   content      proxied
MANAGED_RECORDS=(
  "wiki     CNAME  tecronin.uk  true"
  "weather  CNAME  tecronin.uk  true"
  # WireGuard is UDP 51820. Cloudflare cannot proxy it, and this is the way back
  # in to every service being made private, so it stays grey. Explicit rather
  # than inherited from "*" so the wildcard can be dropped later without
  # silently killing remote access.
  "vpn      CNAME  tecronin.uk  false"
)

api() {  # method path [json]
  # An array, not an unquoted ${3:+...} expansion, so a body containing a space
  # is passed as one argument rather than word-split.
  local -a data=()
  [ $# -ge 3 ] && data=(--data "$3")
  curl -fsS -X "$1" "https://api.cloudflare.com/client/v4/$2" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H 'Content-Type: application/json' \
    "${data[@]}"
}

zone=$(api GET "zones?name=$ZONE_NAME" | jq -r '.result[0].id')

for spec in "${MANAGED_RECORDS[@]}"; do
  read -r name type content proxied <<<"$spec"
  fqdn="$name.$ZONE_NAME"
  body=$(jq -nc --arg t "$type" --arg n "$fqdn" --arg c "$content" --argjson p "$proxied" \
    '{type:$t, name:$n, content:$c, proxied:$p, ttl:1}')
  id=$(api GET "zones/$zone/dns_records?name=$fqdn" | jq -r '.result[0].id // empty')
  if [ -n "$id" ]; then
    api PUT "zones/$zone/dns_records/$id" "$body" >/dev/null && echo "updated $fqdn"
  else
    api POST "zones/$zone/dns_records" "$body" >/dev/null && echo "created $fqdn"
  fi
done

# CAA. Matched on tag+value rather than name, since every CAA record shares the
# apex name and a name-only lookup would collide. Cloudflare injects its own
# partner CAs once any CAA record exists, so these are additive, never pruned.
caa=$(api GET "zones/$zone/dns_records?type=CAA&per_page=100")
for tag in issue issuewild; do
  body=$(jq -nc --arg n "$ZONE_NAME" --arg t "$tag" \
    '{type:"CAA", name:$n, data:{flags:0, tag:$t, value:"letsencrypt.org"}, ttl:1}')
  id=$(jq -r --arg t "$tag" \
    '.result[] | select(.data.tag==$t and .data.value=="letsencrypt.org") | .id' <<<"$caa")
  if [ -n "$id" ]; then
    api PUT "zones/$zone/dns_records/$id" "$body" >/dev/null && echo "updated CAA $tag"
  else
    api POST "zones/$zone/dns_records" "$body" >/dev/null && echo "created CAA $tag"
  fi
done

# Zone-wide, not per-record. Required so Cloudflare validates the origin's
# Let's Encrypt wildcard instead of trusting it blindly or downgrading to HTTP.
api PATCH "zones/$zone/settings/ssl" '{"value":"strict"}' >/dev/null
echo "ssl mode: strict"

# Edge hygiene, also zone-wide and also Zone Settings:Edit. Both only affect
# the two proxied names; grey records never touch the edge.
api PATCH "zones/$zone/settings/always_use_https" '{"value":"on"}' >/dev/null
echo "always use https: on"
api PATCH "zones/$zone/settings/min_tls_version" '{"value":"1.2"}' >/dev/null
echo "min tls: 1.2"
