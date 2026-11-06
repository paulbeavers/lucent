// The workspace row: 1 to 5 always, 6 to 10 while something is on them.
// Click to go there; scroll for the previous or next one on this monitor.
//
// Clicks go through Hypr.focusWorkspace, which sends an hl.dsp dispatch
// through hyprctl: a Lua-configured Hyprland rejects the old `dispatch
// workspace N`, and Quickshell 0.2.1's own Hyprland.dispatch does not know
// about Lua configs (see Hypr.qml).
//
// The active one is a mauve pill, urgent red, occupied in the text colour,
// empty in overlay.

import QtQuick

Row {
    id: row

    property var screen
    readonly property int persistent: 5
    readonly property int active: Hypr.activeWorkspaceOn(screen)

    Repeater {
        model: 10

        delegate: Pill {
            required property int index
            readonly property int n: index + 1
            readonly property int count: Hypr.windowCount(n)
            readonly property bool isActive: row.active === n
            readonly property bool isUrgent: !isActive && Hypr.hasUrgent(n)

            text: n <= row.persistent || count > 0 || isActive ? String(n) : ""
            padX: isActive ? 14 : 8
            fg: isActive || isUrgent ? Theme.c("crust")
              : count > 0 ? Theme.c("text") : Theme.c("overlay")
            bg: isActive ? Theme.c("mauve") : isUrgent ? Theme.c("red") : "transparent"
            hoverBg: isActive || isUrgent ? bg : Theme.c("surface0")
            hoverFg: isActive || isUrgent ? fg : Theme.c("text")

            onClicked: Hypr.focusWorkspace(n)
            onScrolled: step => Hypr.focusWorkspaceRelative(step > 0 ? "m-1" : "m+1")
        }
    }
}
