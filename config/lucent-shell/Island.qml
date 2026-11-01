// One of the top bar's three floating slabs (waybar's .modules-left, -center
// and -right): translucent base, a 1px border, rounded 12.

import QtQuick

Rectangle {
    default property alias content: row.data

    implicitWidth: row.implicitWidth + 12
    height: Settings.barHeight - 6
    anchors.verticalCenter: parent.verticalCenter
    radius: 12
    color: Theme.alpha("base", 0.85)
    border.width: 1
    border.color: Theme.alpha("surface0", 0.9)

    Row {
        id: row
        anchors.centerIn: parent
    }
}
