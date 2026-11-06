//@ pragma UseQApplication
// lucent-shell: the bar and the dock, drawn by Quickshell.
//
// Started by bar.sh at login (autostart.lua). It reads dock-mode,
// dock-position, dock-pinned and dock-hidden in ~/.config/lucent, and the
// palette theme.sh renders there, colors.css and font.css.
//
// One window per screen in panel style; a top bar and a floating dock per
// screen in dock style. Mode and position are read at start; dock.sh restarts
// the shell when they change. The dock is shown and hidden over IPC, which
// dock.sh sends after writing or removing dock-hidden:
//
//     qs -p ~/.config/lucent-shell ipc call dock hide|show
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
    }
}
