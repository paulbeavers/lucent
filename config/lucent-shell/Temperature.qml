// thermal_zone0 (see scripts/stats.sh); gone if there is none. Just the
// figure: the °C says what it is. Red from 82°C.

import QtQuick

Pill {
    readonly property bool critical: Sys.tempC >= 82
    text: Sys.hasTemp ? Sys.tempC + "°C" : ""
    fg: critical ? Theme.c("red") : Theme.c("yellow")
}
