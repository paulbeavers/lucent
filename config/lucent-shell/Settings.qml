pragma Singleton

// The dock's settings: marker files in ~/.config/lucent that dock.sh writes
// and lucent-config's Dock page reads back. Mode and position are read once:
// dock.sh restarts the shell when either changes. Whether the dock is hidden
// comes from bar.sh at start (LUCENT_DOCK_HIDDEN) and from dock.sh over IPC
// afterwards, because a file's absence cannot be watched.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: settings

    // Panel unless the file says "dock"; bottom unless it says "top", so a
    // missing or unreadable file means the default. lucent-config's Dock page
    // tests `!= dock` the same way.
    readonly property bool panelMode: modeFile.text().trim() !== "dock"
    readonly property string edge: positionFile.text().trim() === "top" ? "top" : "bottom"

    // In dock style the bar is at the top whatever the dock's edge.
    readonly property bool barAtTop: !panelMode || edge === "top"

    property bool dockHidden: Quickshell.env("LUCENT_DOCK_HIDDEN") === "1"
    property bool idleInhibited: false

    // The top bar's islands and the panel strip. 58 holds the dock's 48px
    // buttons with 5px to spare either side (DockRow).
    readonly property int barHeight: 38
    readonly property int panelHeight: 58
    // The room a pill gets: the bar's height less its margins — 4px either
    // side inside the top bar's islands (themselves barHeight - 6), 12px
    // either side in the panel.
    readonly property int pillHeight: panelMode ? panelHeight - 24 : barHeight - 6 - 8

    FileView {
        id: modeFile
        path: Theme.config + "/lucent/dock-mode"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: positionFile
        path: Theme.config + "/lucent/dock-position"
        blockLoading: true
        printErrors: false
    }
}
