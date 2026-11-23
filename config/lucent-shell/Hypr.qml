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
// events, never on a timer, and not while the dock's menu is open or an icon
// is being dragged (holdRefresh): rebuilding the dock's buttons would pull the
// menu, or the icon, out from under the pointer.
//
// Minimized windows are the ones on special:minimized (minimize.lua); they
// are kept apart from `clients`, which leaves out every special workspace.
// Which workspace each monitor shows comes from Quickshell's own tracking.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: hypr

    property var clients: []      // mapped, outside special workspaces, oldest first
    property var minimized: []    // on special:minimized, most recently focused first
    readonly property string minimizedWorkspace: "special:minimized"
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

    // Several dispatches, run in order: separate processes would race.
    function dispatchAll(luas) {
        Quickshell.execDetached(["hyprctl", "--batch",
            luas.map(l => "dispatch " + l).join(" ; ")]);
    }

    function windowSelector(address) {
        return luaString("address:" + address);
    }

    function minimizeWindow(address) {
        dispatch("hl.dsp.window.move({ workspace = " + luaString(minimizedWorkspace)
            + ", follow = false, window = " + windowSelector(address) + " })");
    }

    // Back to `workspaceId`, the one in front of the dock, then focused. A
    // silent move: a plain one out of a special workspace closes whatever
    // special workspace that monitor shows (see minimize.lua). A named
    // workspace, or a screen Quickshell has no monitor for, has no positive
    // id; "e+0" is the one in front of you on the focused monitor, which is
    // where the click was.
    function restoreWindow(address, workspaceId) {
        const target = workspaceId > 0 ? String(workspaceId) : luaString("e+0");
        dispatchAll([
            "hl.dsp.window.move({ workspace = " + target
                + ", follow = false, window = " + windowSelector(address) + " })",
            "hl.dsp.focus({ window = " + windowSelector(address) + " })"
        ]);
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
                const named = w => String((w.workspace || {}).name || "");
                const real = w => w.mapped !== false && (w.class || w.initialClass);
                hypr.clients = list.filter(w => real(w) && !named(w).startsWith("special"));
                hypr.minimized = list
                    .filter(w => real(w) && named(w) === hypr.minimizedWorkspace)
                    .sort((a, b) => (a.focusHistoryID ?? 1e9) - (b.focusHistoryID ?? 1e9));
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
