pragma Singleton

// The dock's settings, the same marker files the GTK dock and waybar.sh read.
// Mode and position are read once: dock.sh restarts the shell when either
// changes. Whether the dock is hidden comes from bar.sh at start
// (LUCENT_DOCK_HIDDEN) and from dock.sh over IPC afterwards, because a file's
// absence cannot be watched.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: settings

    // Panel unless the file says "dock"; bottom unless it says "top". The
    // same tests waybar.sh, dock.sh and dock.py make.
    readonly property bool panelMode: modeFile.text().trim() !== "dock"
    readonly property string edge: positionFile.text().trim() === "top" ? "top" : "bottom"

    // In dock style the bar is at the top whatever the dock's edge.
    readonly property bool barAtTop: !panelMode || edge === "top"

    property bool dockHidden: Quickshell.env("LUCENT_DOCK_HIDDEN") === "1"
    property bool idleInhibited: false

    readonly property int barHeight: 38        // waybar/config.jsonc's height
    readonly property int panelHeight: 58      // waybar/panel.jsonc's height
    // The room a pill gets: the bar's height less its margins, as waybar's
    // CSS gave it (4px in the top bar's islands, 12px in the panel).
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
