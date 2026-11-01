// The dock's icons: one per app, pinned or running, with a dot per window,
// then a separator and the launcher. Drawn on a slab of its own in dock style
// (DockWindow) and straight onto the panel in panel style (PanelBar).
//
//     left click     open the app, or focus its window; again cycles its windows
//     middle click   a new window
//     right click    its windows, New window, Pin / Unpin, Close

import QtQuick
import Quickshell
import Quickshell.Hyprland

Row {
    id: dock

    readonly property int iconSize: 40
    readonly property int maxDots: 3
    // Popups open away from the edge the dock is on.
    readonly property bool popupsBelow: Settings.edge === "top"

    spacing: 2

    Repeater {
        model: Apps.list

        delegate: Rectangle {
            id: button
            required property var modelData
            readonly property var app: modelData

            width: dock.iconSize + 10
            // The icon and its dots are 46px; 48 leaves the highlight 5px
            // clear of the 58px panel's edges.
            height: dock.iconSize + 8
            anchors.verticalCenter: parent.verticalCenter
            radius: 10
            color: app.active ? Theme.alpha("surface1", 0.9)
                 : mouse.containsMouse ? Theme.alpha("surface1", 0.7)
                 : "transparent"

            Column {
                anchors.centerIn: parent
                spacing: 2

                // The dots sit between the icon and the screen edge, as on a Mac.
                Dots { visible: Settings.edge === "top"; app: button.app }
                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: dock.iconSize
                    height: dock.iconSize
                    // Logical size; Qt asks the icon for size × the output's
                    // scale, which is what keeps it sharp at 1.33.
                    sourceSize.width: dock.iconSize
                    sourceSize.height: dock.iconSize
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    source: button.app.icon
                }
                Dots { visible: Settings.edge === "bottom"; app: button.app }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: event => {
                    if (event.button === Qt.LeftButton)
                        Apps.activate(button.app);
                    else if (event.button === Qt.MiddleButton)
                        Apps.launch(button.app);
                    else
                        menu.openFor(button, button.app);
                }
            }

            HoverTip {
                text: button.app.name
                below: dock.popupsBelow
                hovered: mouse.containsMouse && !menu.visible
            }
        }
    }

    Item {
        width: 14
        height: dock.iconSize
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            anchors.centerIn: parent
            width: 2
            height: parent.height - 8
            color: Theme.alpha("surface1", 0.9)
        }
    }

    // All apps: a 3×3 grid drawn here rather than a symbolic icon, which
    // Qt would not recolour to the theme.
    Rectangle {
        width: dock.iconSize + 10
        height: dock.iconSize + 8
        anchors.verticalCenter: parent.verticalCenter
        radius: 10
        color: launcherMouse.containsMouse ? Theme.alpha("surface1", 0.7) : "transparent"

        Grid {
            anchors.centerIn: parent
            columns: 3
            spacing: 4
            Repeater {
                model: 9
                delegate: Rectangle {
                    width: 6
                    height: 6
                    radius: 1.5
                    color: launcherMouse.containsMouse ? Theme.c("text") : Theme.c("subtext")
                }
            }
        }

        MouseArea {
            id: launcherMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: Apps.openLauncher()
        }

        HoverTip {
            text: "All apps"
            below: dock.popupsBelow
            hovered: launcherMouse.containsMouse
        }
    }

    component Dots: Row {
        property var app
        anchors.horizontalCenter: parent.horizontalCenter
        height: 4
        spacing: 3
        Repeater {
            model: Math.min(app.windows.length, dock.maxDots)
            delegate: Rectangle {
                width: 4
                height: 4
                radius: 2
                color: app.urgent ? Theme.c("red")
                     : app.active ? Theme.c("blue")
                     : Theme.c("subtext")
            }
        }
    }

    // The right-click menu. While it is open the windows are not read again
    // (Hypr.holdRefresh): rebuilding the buttons would take its anchor away.
    PopupWindow {
        id: menu

        property var items: []
        property Item target: null
        property real menuWidth: 160

        function openFor(item, a) {
            const list = [];
            for (const w of a.windows) {
                let title = String(w.title || a.name).trim();
                if (title.length > 48)
                    title = title.slice(0, 47) + "…";
                list.push({ label: title, run: () => Hypr.focusWindow(w.address) });
            }
            if (list.length)
                list.push({ separator: true });
            if (a.entry) {
                list.push({ label: "New window", run: () => Apps.launch(a) });
                list.push(a.pinned
                    ? { label: "Unpin from dock", run: () => Apps.unpin(a.key) }
                    : { label: "Pin to dock", run: () => Apps.pin(a.key) });
            }
            if (a.windows.length) {
                list.push({ separator: true });
                list.push({
                    label: a.windows.length === 1 ? "Close window"
                         : "Close all " + a.windows.length + " windows",
                    run: () => Apps.closeAll(a)
                });
            }
            let widest = 160;
            for (const it of list) {
                if (it.separator)
                    continue;
                metrics.text = it.label;
                widest = Math.max(widest, Math.ceil(metrics.advanceWidth) + 20);
            }
            menuWidth = widest;
            items = list;
            target = item;
            Hypr.holdRefresh = true;
            visible = true;
        }

        function dismiss() {
            visible = false;
        }

        onVisibleChanged: if (!visible) Hypr.holdRefresh = false

        anchor.window: dock.QsWindow.window
        anchor.item: target
        anchor.edges: dock.popupsBelow ? Edges.Bottom : Edges.Top
        anchor.gravity: dock.popupsBelow ? Edges.Bottom : Edges.Top
        anchor.adjustment: PopupAdjustment.Slide
        color: "transparent"
        implicitWidth: menuWidth + 12
        implicitHeight: menuColumn.implicitHeight + 12

        TextMetrics {
            id: metrics
            font.family: Theme.font
            font.pixelSize: 13
        }

        // A click anywhere outside the menu closes it.
        HyprlandFocusGrab {
            windows: [menu]
            active: menu.visible
            onCleared: menu.dismiss()
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.c("base")
            border.width: 2
            border.color: Theme.c("surface1")

            Column {
                id: menuColumn
                anchors.centerIn: parent
                width: menu.menuWidth

                Repeater {
                    model: menu.items
                    delegate: Item {
                        id: menuItem
                        required property var modelData
                        width: menuColumn.width
                        height: modelData.separator ? 7 : itemText.implicitHeight + 8

                        Rectangle {
                            visible: menuItem.modelData.separator === true
                            anchors.centerIn: parent
                            width: parent.width - 8
                            height: 1
                            color: Theme.c("surface1")
                        }

                        Rectangle {
                            visible: !menuItem.modelData.separator
                            anchors.fill: parent
                            radius: 8
                            color: itemMouse.containsMouse ? Theme.c("surface0") : "transparent"

                            Text {
                                id: itemText
                                anchors.verticalCenter: parent.verticalCenter
                                x: 10
                                text: menuItem.modelData.label || ""
                                color: Theme.c("text")
                                font.family: Theme.font
                                font.pixelSize: 13
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    const run = menuItem.modelData.run;
                                    menu.dismiss();
                                    run();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
