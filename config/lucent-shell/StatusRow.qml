// The right-hand modules, in waybar's order. No network module: nm-applet's
// icon in the tray already shows the connection and opens its menu.

import QtQuick

Row {
    Tray { anchors.verticalCenter: parent.verticalCenter }
    Privacy { anchors.verticalCenter: parent.verticalCenter }
    IdleInhibit { anchors.verticalCenter: parent.verticalCenter }
    Audio { anchors.verticalCenter: parent.verticalCenter }
    Bluetooth { anchors.verticalCenter: parent.verticalCenter }
    Cpu { anchors.verticalCenter: parent.verticalCenter }
    Memory { anchors.verticalCenter: parent.verticalCenter }
    Temperature { anchors.verticalCenter: parent.verticalCenter }
    Battery { anchors.verticalCenter: parent.verticalCenter }
}
