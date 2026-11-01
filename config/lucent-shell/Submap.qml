// The active submap (resize mode and the like), a peach pill while one is on.

import QtQuick

Pill {
    text: Hypr.submap !== "" && Hypr.submap !== "reset" ? "  " + Hypr.submap : ""
    bg: Theme.c("peach")
    fg: Theme.c("crust")
}
