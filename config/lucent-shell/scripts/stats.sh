#!/bin/sh
# The bar's system figures, one per line, for Sys.qml to parse. Run every few
# seconds; everything here is a read of /proc or /sys, so it costs nothing.
#
#     cpu <the cpu line of /proc/stat, without the label>
#     mem <MemTotal kB> <MemAvailable kB>
#     temp <millidegrees>              absent when there is no thermal zone
#     bat <capacity> <status>          absent on a machine with no battery
#     ac <0|1>                         absent with no mains supply
set -u
read -r _ rest < /proc/stat && echo "cpu $rest"
awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { print "mem", t, a }' /proc/meminfo
# waybar's temperature module read thermal_zone0 by default; so does this.
[ -r /sys/class/thermal/thermal_zone0/temp ] \
    && echo "temp $(cat /sys/class/thermal/thermal_zone0/temp)"
for d in /sys/class/power_supply/*; do
    [ -r "$d/type" ] || continue
    case "$(cat "$d/type")" in
        Battery)
            [ -r "$d/capacity" ] && echo "bat $(cat "$d/capacity") $(cat "$d/status" 2>/dev/null)" ;;
        Mains)
            echo "ac $(cat "$d/online" 2>/dev/null || echo 0)" ;;
    esac
done
