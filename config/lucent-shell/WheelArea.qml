// Scrolling where the dock or panel has nothing of its own under the pointer:
// the previous or next workspace on this monitor, as over the workspace row.
// Put it under the content; anything above that takes the wheel (an icon
// cycling its windows, the volume) keeps it.

import QtQuick

MouseArea {
    acceptedButtons: Qt.NoButton

    property real wheel: 0

    onWheel: event => {
        wheel += event.angleDelta.y;
        while (Math.abs(wheel) >= 120) {
            const step = wheel > 0 ? 1 : -1;
            wheel -= step * 120;
            Hypr.focusWorkspaceRelative(step > 0 ? "m-1" : "m+1");
        }
    }
}
