// Keep the screen awake. The inhibitor itself lives on each bar window
// (IdleInhibitor needs a surface); this is the switch. It is held only in
// memory, so it is forgotten when the shell restarts.

import QtQuick

Pill {
    text: Settings.idleInhibited ? "\u{f0176}" : "\u{f06ca}"
    fg: Settings.idleInhibited ? Theme.c("peach") : Theme.c("subtext")
    tip: Settings.idleInhibited ? "Idle inhibited — screen will not lock" : "Idle normal"
    onClicked: Settings.idleInhibited = !Settings.idleInhibited
}
