// The dock's icons: one per app, pinned or running, with a dot per window,
// then a separator, the minimized windows and the launcher. Drawn on a slab
// of its own in dock style (DockWindow) and straight onto the panel in panel
// style (PanelBar).
//
//     left click     open the app, or focus its window; again cycles its windows
//     middle click   a new window
//     right click    its windows, New window, Pin / Unpin, Close
//     drag           reorder the pins; drag a running app in among them to pin
//                    it, or a pinned one up off the dock to unpin it
//
// A minimized window (minimize.lua) is an icon of its own after the
// separator; a click brings it back to the workspace in front of you.
//
// With Settings.scopeWorkspace the dock lists only the apps with a window on
// that workspace, plus the pinned ones, and an app's dots and clicks only
// count its windows there.

import QtQuick
import Quickshell
import Quickshell.Hyprland

Row {
    id: dock

    property var screen
    readonly property int workspace: Hypr.activeWorkspaceOn(screen)
    readonly property var apps: Settings.scopeWorkspace
        ? Apps.forWorkspace(Apps.list, workspace) : Apps.list

    readonly property int iconSize: 40
    readonly property int maxDots: 3
    readonly property int slot: iconSize + 10 + spacing
    // Popups open away from the edge the dock is on.
    readonly property bool popupsBelow: Settings.edge === "top"
    // Something the dock must stay out for: auto-hide waits on it.
    readonly property bool busy: menu.visible || dragIndex >= 0

    // ── dragging ────────────────────────────────────────────────────────────
    // The buttons are not moved while a drag is on, only drawn offset: the
    // Repeater rebuilds every button when the list changes, which would take
    // the one under the pointer away. Window events are held off meanwhile
    // (Hypr.holdRefresh), and the order is saved on release.
    property int dragIndex: -1
    property real dragDx: 0
    property real dragDy: 0
    readonly property int pinnedCount: apps.filter(a => a.pinned).length
    readonly property bool dragPinned: dragIndex >= 0 && dragIndex < apps.length
        && apps[dragIndex].pinned
    // Up off the dock (or down, at the top), far enough to mean "remove".
    readonly property bool dragOff: dragPinned
        && (Settings.edge === "top" ? dragDy : -dragDy) > iconSize

    function dropIndex() {
        if (dragIndex < 0 || dragOff)
            return -1;
        const t = dragIndex + Math.round(dragDx / slot);
        if (dragPinned)
            return Math.max(0, Math.min(t, pinnedCount - 1));
        // A running app pins only if it is dragged in among the pins.
        return t < dragIndex ? Math.max(0, Math.min(t, pinnedCount)) : -1;
    }

    function offsetFor(index) {
        if (dragIndex < 0)
            return 0;
        if (index === dragIndex)
            return dragDx;
        const t = dropIndex();
        if (t < 0 || t === dragIndex)
            return 0;
        if (dragIndex < t && index > dragIndex && index <= t)
            return -slot;
        if (t < dragIndex && index >= t && index < dragIndex)
            return slot;
        return 0;
    }

    function startDrag(index) {
        dragIndex = index;
        Hypr.holdRefresh = true;
    }

    function resetDrag() {
        dragIndex = -1;
        dragDx = 0;
        dragDy = 0;
        Hypr.holdRefresh = menu.visible;
    }

    function endDrag() {
        const a = apps[dragIndex];
        const t = dropIndex();
        const off = dragOff;
        resetDrag();
        if (!a)
            return;
        if (off)
            Apps.unpin(a.key);
        else if (t >= 0 && (t !== apps.indexOf(a) || !a.pinned))
            Apps.pinAt(a.key, t, apps.filter(x => x.pinned).map(x => x.key));
    }

    // Held refreshes stop window events, not everything: a launch timing out
    // or an app being installed still rebuilds the list, and the button being
    // dragged goes with it. Drop the drag rather than leave it hanging.
    onAppsChanged: if (dragIndex >= 0) resetDrag()

    spacing: 2

    Repeater {
        model: dock.apps

        delegate: Rectangle {
            id: button
            required property var modelData
            required property int index
            readonly property var app: modelData
            readonly property bool dragged: dock.dragIndex === index

            width: dock.iconSize + 10
            // The icon and its dots are 46px; 48 leaves the highlight 5px
            // clear of the 58px panel's edges.
            height: dock.iconSize + 8
            anchors.verticalCenter: parent.verticalCenter
            radius: 10
            z: dragged ? 10 : 0
            opacity: dragged && dock.dragOff ? 0.35 : 1
            transform: Translate {
                x: dock.offsetFor(button.index)
                Behavior on x {
                    enabled: !button.dragged
                    NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                }
            }
            color: app.active || dragged ? Theme.alpha("surface1", 0.9)
                 : mouse.containsMouse ? Theme.alpha("surface1", 0.7)
                 : "transparent"

            Column {
                anchors.centerIn: parent
                spacing: 2

                // The dots sit between the icon and the screen edge, as on a Mac.
                Dots { visible: Settings.edge === "top"; app: button.app }
                Image {
                    id: icon
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

            // Starting up: the icon breathes until the app has a new window.
            SequentialAnimation {
                running: button.app.launching
                loops: Animation.Infinite
                onStopped: icon.opacity = 1
                NumberAnimation {
                    target: icon; property: "opacity"; to: 0.35
                    duration: 450; easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: icon; property: "opacity"; to: 1
                    duration: 450; easing.type: Easing.InOutQuad
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                property real pressX: 0
                property real pressY: 0
                property bool dragging: false
                property bool swallowClick: false

                onPressed: event => {
                    pressX = event.x;
                    pressY = event.y;
                    swallowClick = false;
                }
                onPositionChanged: event => {
                    if (!(event.buttons & Qt.LeftButton))
                        return;
                    const dx = event.x - pressX;
                    const dy = event.y - pressY;
                    // Only an app with a desktop file can be pinned, so only
                    // those drag.
                    if (!dragging && button.app.entry
                            && Math.abs(dx) + Math.abs(dy) > 10) {
                        dragging = true;
                        dock.startDrag(button.index);
                    }
                    if (dragging) {
                        dock.dragDx = dx;
                        dock.dragDy = dy;
                    }
                }
                onReleased: {
                    if (dragging) {
                        dragging = false;
                        swallowClick = true;
                        dock.endDrag();
                    }
                }
                onCanceled: {
                    if (dragging) {
                        dragging = false;
                        dock.resetDrag();
                    }
                }
                onClicked: event => {
                    if (swallowClick) {
                        swallowClick = false;
                        return;
                    }
                    if (event.button === Qt.LeftButton)
                        Apps.activate(button.app, dock.workspace);
                    else if (event.button === Qt.MiddleButton)
                        Apps.launch(button.app);
                    else
                        menu.openFor(button, button.app);
                }
            }

            HoverTip {
                text: button.app.name
                below: dock.popupsBelow
                hovered: mouse.containsMouse && !menu.visible && !button.dragged
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

    // Minimized windows, one each, most recently focused first. A smaller icon
    // on a card, so it reads as a window put away rather than another app.
    Repeater {
        model: Hypr.minimized

        delegate: Rectangle {
            id: parked
            required property var modelData
            readonly property var win: modelData
            readonly property string title: String(win.title || win.class || "").trim()

            width: dock.iconSize + 10
            height: dock.iconSize + 8
            anchors.verticalCenter: parent.verticalCenter
            radius: 10
            color: parkedMouse.containsMouse ? Theme.alpha("surface1", 0.7) : "transparent"

            Rectangle {
                anchors.centerIn: parent
                width: dock.iconSize - 2
                height: dock.iconSize - 6
                radius: 7
                color: Theme.alpha("surface0", 0.9)
                border.width: 1
                border.color: Theme.alpha("surface1", 0.9)

                Image {
                    anchors.centerIn: parent
                    width: dock.iconSize - 14
                    height: dock.iconSize - 14
                    sourceSize.width: dock.iconSize - 14
                    sourceSize.height: dock.iconSize - 14
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    source: Apps.windowIcon(parked.win)
                }
            }

            MouseArea {
                id: parkedMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: event => {
                    if (event.button === Qt.LeftButton)
                        Hypr.restoreWindow(parked.win.address, dock.workspace);
                    else
                        menu.openWith(parked, [
                            { label: "Restore", run: () => Hypr.restoreWindow(parked.win.address, dock.workspace) },
                            { separator: true },
                            { label: "Close window", run: () => Hypr.closeWindow(parked.win.address) }
                        ]);
                }
            }

            HoverTip {
                text: parked.title.length > 60 ? parked.title.slice(0, 59) + "…" : parked.title
                below: dock.popupsBelow
                hovered: parkedMouse.containsMouse && !menu.visible
            }
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

    // A dot per window, minimized ones included: the app is running.
    component Dots: Row {
        property var app
        anchors.horizontalCenter: parent.horizontalCenter
        height: 4
        spacing: 3
        Repeater {
            model: Math.min(app.windows.length + app.minimized.length, dock.maxDots)
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

        function shorten(title) {
            title = String(title).trim();
            return title.length > 48 ? title.slice(0, 47) + "…" : title;
        }

        function openFor(item, a) {
            const list = [];
            for (const w of a.windows)
                list.push({ label: shorten(w.title || a.name), run: () => Hypr.focusWindow(w.address) });
            for (const w of a.minimized)
                list.push({
                    label: shorten(w.title || a.name) + "  (minimized)",
                    run: () => Hypr.restoreWindow(w.address, dock.workspace)
                });
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
            openWith(item, list);
        }

        function openWith(item, list) {
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

        onVisibleChanged: if (!visible && dock.dragIndex < 0) Hypr.holdRefresh = false

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
