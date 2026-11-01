//@ pragma UseQApplication
// lucent-shell: the bar and the dock, drawn by Quickshell.
//
// Chosen with `bar.sh --engine quickshell` (lucent-config's Dock page, "Bar
// and dock"), recorded in ~/.config/lucent/shell-engine. The other engine is
// waybar plus the GTK dock (lucent-dock/dock.py), and the default. Both read
// the same files — dock-mode, dock-position, dock-pinned, waybar/colors.css —
// so switching changes nothing else.
//
// One window per screen in panel style; a top bar and a floating dock per
// screen in dock style. Mode and position are read at start; dock.sh restarts
// the shell when they change. The dock is shown and hidden over IPC:
//
//     qs -p ~/.config/lucent-shell ipc call dock hide|show|toggle
//
// UseQApplication: the tray's menus are platform menus, which need it.

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    Variants {
        model: Settings.panelMode ? Quickshell.screens : []
        delegate: PanelBar {
            required property var modelData
            screen: modelData
        }
    }

    Variants {
        model: Settings.panelMode ? [] : Quickshell.screens
        delegate: BarWindow {
            required property var modelData
            screen: modelData
        }
    }

    Variants {
        model: Settings.panelMode ? [] : Quickshell.screens
        delegate: DockWindow {
            required property var modelData
            screen: modelData
        }
    }

    IpcHandler {
        target: "dock"
        function show(): void { Settings.dockHidden = false; }
        function hide(): void { Settings.dockHidden = true; }
        function toggle(): void { Settings.dockHidden = !Settings.dockHidden; }
    }
}
