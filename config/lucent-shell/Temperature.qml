// thermal_zone0, as waybar read it by default; gone if there is none.

import QtQuick

Pill {
    readonly property bool critical: Sys.tempC >= 82
    text: Sys.hasTemp ? (critical ? "" : "") + "  " + Sys.tempC + "°C" : ""
    fg: critical ? Theme.c("red") : Theme.c("yellow")
}
