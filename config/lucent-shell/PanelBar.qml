// Panel style, the default: one strip across the screen edge holding the
// workspaces with the dock right after them, and the status modules with the
// date and time at the other end.
//
// With waybar this was two programs composed — waybar drawing the strip and
// the GTK dock drawing its icons on top with no zone of its own, which had to
// map after waybar and map again whenever waybar reloaded. Here it is one
// window, so none of that applies.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: panel

    WlrLayershell.namespace: "lucent-bar"
    WlrLayershell.layer: WlrLayer.Top

    anchors.bottom: Settings.edge === "bottom"
    anchors.top: Settings.edge === "top"
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Auto

    implicitHeight: Settings.panelHeight
    color: Theme.alpha("base", 0.92)

    IdleInhibitor {
        window: panel
        enabled: Settings.idleInhibited
    }

    // waybar's border-top, on whichever side faces the desktop.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        y: Settings.edge === "bottom" ? 0 : parent.height - 1
        height: 1
        color: Theme.alpha("surface1", 0.9)
    }

    Row {
        id: left
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        Workspaces { screen: panel.screen; anchors.verticalCenter: parent.verticalCenter }
        Submap { anchors.verticalCenter: parent.verticalCenter }
    }

    // The dock follows the workspaces, rather than sitting in the middle:
    // the apps are next to where the eye already is on that side.
    DockRow {
        anchors.left: left.right
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
