import QtQuick

Pill {
    icon: "\uf4bc"
    text: Sys.cpu + "%"
    fg: Theme.c("peach")
    onClicked: Apps.run([Theme.config + "/hypr/scripts/terminal.sh", "--class", "floating-term", "-e", "btop"])
}
