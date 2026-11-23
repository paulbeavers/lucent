// The dock in dock style: its own slab, floating 6px off the screen edge and
// reserving its height, so windows tile beside it rather than under it.
// Hidden (SUPER+D) means unmapped, which gives that space back.
//
// Auto-hide (Settings.autohide) reserves nothing: windows take the whole
// screen, and the slab sits off the edge until the pointer reaches it. The
// window then spans the edge, so the pointer can come at it anywhere along
// it, and its input region (mask) is only a strip at the edge while the slab
// is away, so the windows underneath still get their clicks. Once out, the
// region is the slab and the space down to the edge, plus the strip, so a
// pointer resting on the edge beside the slab keeps it out rather than
// flickering it.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win

    WlrLayershell.namespace: "lucent-dock"
    WlrLayershell.layer: WlrLayer.Top

    readonly property bool autohide: Settings.autohide
    readonly property int gap: 6
    readonly property bool atTop: Settings.edge === "top"

    anchors.bottom: !atTop
    anchors.top: atTop
    anchors.left: autohide
    anchors.right: autohide
    margins.bottom: autohide ? 0 : gap
    margins.top: autohide ? 0 : gap
    exclusionMode: autohide ? ExclusionMode.Ignore : ExclusionMode.Auto

    visible: !Settings.dockHidden
    color: "transparent"
    implicitWidth: slab.width
    implicitHeight: slab.height + (autohide ? gap : 0)

    mask: Region {
        item: shown.revealed ? zone : strip
        Region { item: strip }
    }

    AutoHide {
        id: shown
        active: win.autohide
        hovered: hover.hovered
        busy: row.busy
    }

    Item {
        anchors.fill: parent

        HoverHandler { id: hover }

        // The slab and the space between it and the edge.
        Item {
            id: zone
            x: slab.x
            width: slab.width
            y: win.atTop ? 0 : slab.y
            height: win.atTop ? slab.y + slab.height : parent.height - slab.y
        }

        Item {
            id: strip
            width: parent.width
            height: 3
            y: win.atTop ? 0 : parent.height - height
        }

        Rectangle {
            id: slab
            width: row.implicitWidth + 16
            height: row.implicitHeight + 8
            x: (parent.width - width) / 2
            y: shown.revealed ? (win.atTop && win.autohide ? win.gap : 0)
             : win.atTop ? -height : parent.height
            radius: 14
            color: Theme.alpha("base", 0.85)
            border.width: 2
            border.color: Theme.alpha("surface1", 0.9)

            Behavior on y {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            DockRow {
                id: row
                anchors.centerIn: parent
                screen: win.screen
            }
        }
    }
}
