pragma Singleton

// Hyprland: the windows, the submap, and the dispatches.
//
// lucent's Hyprland is configured in Lua, which evaluates everything after
// `dispatch` as Lua, so every request here is an hl.dsp call, sent through
// hyprctl as the scripts send theirs. Quickshell 0.3's own Hyprland.dispatch
// knows about Lua configs; 0.2.1 (Fedora 44's) does not, and this works on
// both.
//
// The windows are `hyprctl -j clients`, read again after window and workspace
// events, never on a timer, and not while the dock's menu is open (holdRefresh):
// rebuilding the dock's buttons would pull the menu out from under the pointer.
// Which workspace each monitor shows comes from Quickshell's own tracking.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: hypr

    property var clients: []      // mapped, outside special workspaces, oldest first
    property string activeAddress: ""
    property string submap: ""
    property bool holdRefresh: false
    property bool stale: false

    readonly property var events: [
        "openwindow", "closewindow", "activewindowv2", "movewindowv2",
        "windowtitlev2", "urgent", "workspacev2", "createworkspacev2",
        "destroyworkspacev2", "moveworkspacev2", "focusedmonv2"
    ]

    onHoldRefreshChanged: if (!holdRefresh && stale) refreshTimer.restart()

    function luaString(s) {
        return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
    }

    function dispatch(lua) {
        Quickshell.execDetached(["hyprctl", "dispatch", lua]);
    }

    function focusWindow(address) {
        dispatch("hl.dsp.focus({ window = " + luaString("address:" + address) + " })");
    }

    function closeWindow(address) {
        dispatch("hl.dsp.window.close({ window = " + luaString("address:" + address) + " })");
    }

    function focusWorkspace(n) {
        dispatch("hl.dsp.focus({ workspace = " + n + " })");
    }

    // "m-1" / "m+1": the previous or next workspace on this monitor.
    function focusWorkspaceRelative(spec) {
        dispatch("hl.dsp.focus({ workspace = " + luaString(spec) + " })");
    }

    function windowCount(workspaceId) {
        let n = 0;
        for (const w of clients)
            if ((w.workspace || {}).id === workspaceId)
                n++;
        return n;
    }

    function hasUrgent(workspaceId) {
        return clients.some(w => (w.workspace || {}).id === workspaceId && w.urgent);
    }

    function activeWorkspaceOn(screen) {
        const m = screen ? Hyprland.monitorFor(screen) : null;
        return m && m.activeWorkspace ? m.activeWorkspace.id : -1;
    }

    function refresh() {
        if (holdRefresh) {
            stale = true;
            return;
        }
        stale = false;
        if (clientsProc.running)
            clientsProc.again = true;
        else
            clientsProc.running = true;
    }

    Process {
        id: clientsProc
        property bool again: false
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    list = JSON.parse(text);
                } catch (e) {
                    list = [];
                }
                hypr.clients = list.filter(w =>
                    w.mapped !== false
                    && !String((w.workspace || {}).name || "").startsWith("special")
                    && (w.class || w.initialClass));
                const active = list.find(w => w.focusHistoryID === 0);
                hypr.activeAddress = active ? active.address : "";
            }
        }
        onExited: {
            if (again) {
                again = false;
                running = true;
            }
        }
    }

    // Events arrive in bursts (a window opening is four or five); one read
    // covers the lot.
    Timer {
        id: refreshTimer
        interval: 40
        onTriggered: hypr.refresh()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap")
                hypr.submap = event.data;
            else if (hypr.events.indexOf(event.name) >= 0)
                refreshTimer.restart();
        }
    }

    Component.onCompleted: refresh()
}
