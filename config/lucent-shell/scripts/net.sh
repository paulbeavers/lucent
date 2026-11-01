#!/bin/sh
# The bar's network figures, key=value per line, for Sys.qml to parse.
#
# NetworkManager is what every lucent desktop runs, so nmcli is the one place
# to ask. The first wired or wireless device that is connected wins; failing
# that, one that is still connecting (waybar called that "linked").
#
#     dev= type=wifi|ethernet state= signal= ssid= ip= rx= tx=
set -u
devices=$(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null) || exit 0
line=$(printf '%s\n' "$devices" | awk -F: '($2 == "wifi" || $2 == "ethernet") && $3 ~ /^connected/ { print; exit }')
[ -n "$line" ] || line=$(printf '%s\n' "$devices" | awk -F: '($2 == "wifi" || $2 == "ethernet") && $3 ~ /^connecting/ { print; exit }')
[ -n "$line" ] || { echo "state=disconnected"; exit 0; }

dev=${line%%:*}; rest=${line#*:}
type=${rest%%:*}; state=${rest#*:}
echo "dev=$dev"
echo "type=$type"
echo "state=$state"
if [ "$type" = wifi ]; then
    nmcli -t -f IN-USE,SIGNAL,SSID device wifi list ifname "$dev" --rescan no 2>/dev/null \
        | awk -F: '$1 == "*" { print "signal=" $2; sub(/^\*:[0-9]+:/, ""); gsub(/\\:/, ":"); print "ssid=" $0; exit }'
fi
echo "ip=$(ip -4 -o addr show dev "$dev" 2>/dev/null | awk '{ print $4; exit }')"
echo "rx=$(cat "/sys/class/net/$dev/statistics/rx_bytes" 2>/dev/null || echo 0)"
echo "tx=$(cat "/sys/class/net/$dev/statistics/tx_bytes" 2>/dev/null || echo 0)"
