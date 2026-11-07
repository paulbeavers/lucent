// The top bar, in dock style: three islands across the top of each screen —
// workspaces and submap; the clock; the status modules.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: bar

    WlrLayershell.namespace: "lucent-bar"
    WlrLayershell.layer: WlrLayer.Top

    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: 6
    margins.left: 10
    margins.right: 10
    exclusionMode: ExclusionMode.Auto

    implicitHeight: Settings.barHeight
    color: "transparent"

    IdleInhibitor {
        window: bar
        enabled: Settings.idleInhibited
    }

    Island {
        anchors.left: parent.left
        Workspaces { screen: bar.screen; anchors.verticalCenter: parent.verticalCenter }
        Submap { anchors.verticalCenter: parent.verticalCenter }
    }

    Island {
        anchors.horizontalCenter: parent.horizontalCenter
        Clock { anchors.verticalCenter: parent.verticalCenter }
    }

    Island {
        anchors.right: parent.right
        StatusRow { anchors.verticalCenter: parent.verticalCenter }
        Power { anchors.verticalCenter: parent.verticalCenter }
    }
}
