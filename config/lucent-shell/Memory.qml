import QtQuick

Pill {
    icon: "\uefc5"
    text: Sys.memPercent + "%"
    fg: Theme.c("mauve")
    tip: (Sys.memUsed / 1048576).toFixed(1) + "G / " + (Sys.memTotal / 1048576).toFixed(1) + "G"
    onClicked: Apps.run([Theme.config + "/hypr/scripts/terminal.sh", "--class", "floating-term", "-e", "btop"])
}
