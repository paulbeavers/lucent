// Panel style, the default: one strip across the screen edge holding the
// workspaces with the dock right after them, and the status modules with the
// date and time at the other end. It is all one window, so the dock needs no
// surface or exclusive zone of its own here.
//
// Auto-hide (Settings.autohide) takes the whole strip off the edge, since the
// dock is part of it, and reserves nothing; it comes back when the pointer
// reaches the edge. While it is away the input region (mask) is a strip at the
// edge, so the windows underneath keep their clicks, and the background is on
// the content rather than the window so nothing is left drawn there.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: panel

    WlrLayershell.namespace: "lucent-bar"
    WlrLayershell.layer: WlrLayer.Top

    readonly property bool atTop: Settings.edge === "top"

    anchors.bottom: !atTop
    anchors.top: atTop
    anchors.left: true
    anchors.right: true
    exclusionMode: Settings.autohide ? ExclusionMode.Ignore : ExclusionMode.Auto

    implicitHeight: Settings.panelHeight
    color: "transparent"

    mask: Region {
        item: shown.revealed ? content : strip
        Region { item: strip }
    }

    IdleInhibitor {
        window: panel
        enabled: Settings.idleInhibited
    }

    AutoHide {
        id: shown
        active: Settings.autohide
        hovered: hover.hovered
        busy: dockRow.busy
    }

    Item {
        anchors.fill: parent

        HoverHandler { id: hover }

        Item {
            id: strip
            width: parent.width
            height: 3
            y: panel.atTop ? 0 : parent.height - height
        }

        Rectangle {
            id: content
            width: parent.width
            height: parent.height
            y: shown.revealed ? 0 : panel.atTop ? -height : height
            color: Theme.alpha("base", 0.92)

            Behavior on y {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            // A 1px border on whichever side faces the desktop.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                y: panel.atTop ? parent.height - 1 : 0
                height: 1
                color: Theme.alpha("surface1", 0.9)
            }

            Row {
                id: workspaceRow
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                Workspaces { screen: panel.screen; anchors.verticalCenter: parent.verticalCenter }
                Submap { anchors.verticalCenter: parent.verticalCenter }
            }

            // The dock follows the workspaces, rather than sitting in the middle:
            // the apps are next to where the eye already is on that side.
            DockRow {
                id: dockRow
                screen: panel.screen
                anchors.left: workspaceRow.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: !Settings.dockHidden
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                StatusRow { anchors.verticalCenter: parent.verticalCenter }
                Clock { anchors.verticalCenter: parent.verticalCenter }
                Power { anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }
}
