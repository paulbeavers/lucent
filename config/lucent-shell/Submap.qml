// The active submap (resize mode and the like), a peach pill while one is on.

import QtQuick

Pill {
    readonly property bool on: Hypr.submap !== "" && Hypr.submap !== "reset"
    icon: on ? "\uf11c" : ""
    text: on ? Hypr.submap : ""
    bg: Theme.c("peach")
    fg: Theme.c("crust")
}
