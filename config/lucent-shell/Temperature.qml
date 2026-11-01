// thermal_zone0, as waybar read it by default; gone if there is none. Just
// the figure: the °C says what it is. Red from 82°C, which the thermometer's
// full/half glyph used to say as well.

import QtQuick

Pill {
    readonly property bool critical: Sys.tempC >= 82
    text: Sys.hasTemp ? Sys.tempC + "°C" : ""
    fg: critical ? Theme.c("red") : Theme.c("yellow")
}
