// The system tray: nm-applet, blueman and anything else that registers.
// Left click activates (or opens the menu, for an item that is only a
// menu), middle click is the secondary action, right click the menu.

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Item {
    id: tray

    visible: SystemTray.items.values.length > 0
    implicitWidth: row.implicitWidth + 24
    implicitHeight: Settings.pillHeight

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 10

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: entry
                required property var modelData
                width: 16
                height: Settings.pillHeight

                Image {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    sourceSize.width: 16
                    sourceSize.height: 16
                    fillMode: Image.PreserveAspectFit
                    source: entry.modelData.icon
                }

                function menu() {
                    if (!modelData.hasMenu)
                        return;
                    const win = QsWindow.window;
                    const p = mapToItem(null, 0, Settings.barAtTop ? height : 0);
                    modelData.display(win, p.x, p.y);
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: event => {
                        if (event.button === Qt.RightButton
                            || (event.button === Qt.LeftButton && entry.modelData.onlyMenu))
                            entry.menu();
                        else if (event.button === Qt.LeftButton)
                            entry.modelData.activate();
                        else
                            entry.modelData.secondaryActivate();
                    }
                    onWheel: event => entry.modelData.scroll(event.angleDelta.y, false)
                }

                HoverTip {
                    text: entry.modelData.tooltipTitle || entry.modelData.title || ""
                    hovered: mouse.containsMouse
                }
            }
        }
    }
}
