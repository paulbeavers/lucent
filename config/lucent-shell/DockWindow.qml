// The dock in dock style: its own slab, floating 6px off the screen edge and
// reserving its height, so windows tile beside it rather than under it.
// Hidden (SUPER+D) means unmapped, which gives that space back.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win

    WlrLayershell.namespace: "lucent-dock"
    WlrLayershell.layer: WlrLayer.Top

    anchors.bottom: Settings.edge === "bottom"
    anchors.top: Settings.edge === "top"
    margins.bottom: 6
    margins.top: 6
    exclusionMode: ExclusionMode.Auto

    visible: !Settings.dockHidden
    color: "transparent"
    implicitWidth: slab.width
    implicitHeight: slab.height

    Rectangle {
        id: slab
        width: row.implicitWidth + 16
        height: row.implicitHeight + 8
        radius: 14
        color: Theme.alpha("base", 0.85)
        border.width: 2
        border.color: Theme.alpha("surface1", 0.9)

        DockRow {
            id: row
            anchors.centerIn: parent
        }
    }
}
