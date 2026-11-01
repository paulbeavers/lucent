// The power menu: wofi, as SUPER+SHIFT+E opens it.

import QtQuick

Pill {
    text: "⏻"
    fg: Theme.c("red")
    hoverBg: Theme.c("red")
    hoverFg: Theme.c("crust")
    padX: 12
    fontSize: 16
    onClicked: Apps.run([Theme.config + "/hypr/scripts/powermenu.sh"])
}
