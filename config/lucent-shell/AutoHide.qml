// Whether an auto-hiding dock or panel is out: at once when the pointer
// reaches it, 400ms after the pointer leaves, and never while it is in use
// (a menu open, an icon being dragged). With `active` false it is always out.

import QtQuick

Item {
    id: root

    property bool active: false
    property bool hovered: false
    property bool busy: false
    property bool revealed: true

    function update() {
        if (!active || hovered || busy) {
            hideTimer.stop();
            revealed = true;
        } else {
            hideTimer.restart();
        }
    }

    onActiveChanged: update()
    onHoveredChanged: update()
    onBusyChanged: update()
    // Out for a moment at login, then away, so it is seen to exist.
    Component.onCompleted: update()

    Timer {
        id: hideTimer
        interval: 400
        onTriggered: root.revealed = false
    }
}
