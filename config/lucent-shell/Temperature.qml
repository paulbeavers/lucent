// thermal_zone0, as waybar read it by default; gone if there is none.

import QtQuick

Pill {
    readonly property bool critical: Sys.tempC >= 82
    icon: Sys.hasTemp ? (critical ? "\uf2c7" : "\uf2c9") : ""
    text: Sys.hasTemp ? Sys.tempC + "°C" : ""
    fg: critical ? Theme.c("red") : Theme.c("yellow")
}
