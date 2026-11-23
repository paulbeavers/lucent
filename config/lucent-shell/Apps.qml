pragma Singleton

// The dock's model: one entry per app, not per window — the pinned apps
// first, then anything else open, in the order first seen.
//
// Pins are ~/.config/lucent/dock-pinned, one desktop file ID per line. With
// no file the defaults below are shown; the file is written the first time a
// pin changes.
//
// An app's minimized windows (Hypr.minimized) count as its windows for being
// listed and for its dots, but are kept apart: focusing one would open the
// special workspace it waits on, so it is brought back instead.
//
// An app launched from the dock is `launching` until it has a window more
// than it had, or for ten seconds, whichever is first; the icon pulses
// meanwhile, so a slow start does not read as a missed click.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: apps

    readonly property var defaultPinned: ["firefox.desktop", "thunar.desktop", "foot.desktop"]

    property var pinned: []
    property var order: []        // keys of unpinned running apps, first seen first
    property var list: []         // what the dock shows, in order
    property var launching: ({})  // key -> { count, until }

    readonly property int launchTimeout: 10000

    FileView {
        id: pinnedFile
        path: Theme.config + "/lucent/dock-pinned"
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: {
            apps.pinned = text().split(/\s+/).filter(s => s.length > 0);
            apps.rebuild();
        }
        onLoadFailed: {
            apps.pinned = apps.defaultPinned.slice();
            apps.rebuild();
        }
    }

    Connections {
        target: Hypr
        function onClientsChanged() { apps.rebuild(); }
        function onActiveAddressChanged() { apps.rebuild(); }
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { apps.rebuild(); }
    }

    Connections {
        target: Hypr
        function onMinimizedChanged() { apps.rebuild(); }
    }

    Timer {
        interval: 1000
        repeat: true
        running: Object.keys(apps.launching).length > 0
        onTriggered: {
            const now = Date.now();
            const left = {};
            let changed = false;
            for (const k in apps.launching) {
                if (apps.launching[k].until > now)
                    left[k] = apps.launching[k];
                else
                    changed = true;
            }
            if (changed) {
                apps.launching = left;
                apps.rebuild();
            }
        }
    }

    function entryById(id) {
        return DesktopEntries.byId(id.replace(/\.desktop$/, ""));
    }

    function iconSource(entry, cls) {
        const name = entry && entry.icon ? entry.icon : (cls || "").toLowerCase();
        if (name.startsWith("/"))
            return "file://" + name;
        return Quickshell.iconPath(name, "application-x-executable");
    }

    // The dock's key for a window's app: its desktop file, or its class.
    function keyFor(w) {
        const cls = w.class || w.initialClass;
        const entry = DesktopEntries.heuristicLookup(cls);
        return { key: entry ? entry.id + ".desktop" : "class:" + cls.toLowerCase(),
                 entry: entry, cls: cls };
    }

    function windowIcon(w) {
        const k = keyFor(w);
        return iconSource(k.entry, k.cls);
    }

    function rebuild() {
        const byKey = {};
        for (const id of pinned) {
            const entry = entryById(id);
            if (entry)
                byKey[id] = { key: id, entry: entry, cls: "", windows: [], minimized: [] };
        }

        const seen = order.slice();
        const add = (w, field) => {
            const k = keyFor(w);
            if (!byKey[k.key]) {
                byKey[k.key] = { key: k.key, entry: k.entry, cls: k.cls, windows: [], minimized: [] };
                if (seen.indexOf(k.key) < 0 && pinned.indexOf(k.key) < 0)
                    seen.push(k.key);
            }
            byKey[k.key].cls = byKey[k.key].cls || k.cls;
            byKey[k.key][field].push(w);
        };
        for (const w of Hypr.clients)
            add(w, "windows");
        for (const w of Hypr.minimized)
            add(w, "minimized");

        // A launch is over once its app has a window more than it had.
        let settled = false;
        const still = {};
        for (const k in launching) {
            const a = byKey[k];
            const n = a ? a.windows.length + a.minimized.length : 0;
            if (n > launching[k].count)
                settled = true;
            else
                still[k] = launching[k];
        }
        if (settled)
            launching = still;

        order = seen.filter(k => byKey[k] && pinned.indexOf(k) < 0);
        const keys = pinned.filter(k => byKey[k]).concat(order);

        list = keys.map(k => describe(byKey[k], byKey[k].windows));
    }

    function describe(a, windows) {
        return {
            key: a.key,
            entry: a.entry,
            cls: a.cls,
            name: a.entry ? a.entry.name : (a.cls || a.key),
            icon: iconSource(a.entry, a.cls),
            windows: windows,
            allWindows: a.windows,
            minimized: a.minimized,
            active: windows.some(w => w.address === Hypr.activeAddress),
            urgent: windows.some(w => w.urgent),
            pinned: pinned.indexOf(a.key) >= 0,
            launching: launching[a.key] !== undefined
        };
    }

    // The dock for one workspace (Settings.scopeWorkspace): each app's windows
    // there, and only the apps that have some, are pinned, or have a window
    // minimized.
    function forWorkspace(all, workspaceId) {
        const out = [];
        for (const a of all) {
            const here = a.allWindows.filter(w => (w.workspace || {}).id === workspaceId);
            if (a.pinned || here.length > 0 || a.minimized.length > 0)
                out.push(describe(a, here));
        }
        return out;
    }

    function savePinned(ids) {
        pinned = ids;
        pinnedFile.setText(ids.map(i => i + "\n").join(""));
        rebuild();
    }

    // Anything the shell starts gets GTK_THEME as it is now (Theme.gtkTheme).
    function run(command, workingDirectory) {
        Quickshell.execDetached({
            command: command,
            workingDirectory: workingDirectory || Quickshell.env("HOME"),
            environment: { GTK_THEME: Theme.gtkTheme() }
        });
    }

    function launch(app) {
        const entry = app.entry || entryById(app.key);
        if (!entry)
            return;
        let command = Array.from(entry.command);
        if (entry.runInTerminal)
            command = [Theme.config + "/hypr/scripts/terminal.sh"].concat(command);
        run(command, entry.workingDirectory);

        const next = Object.assign({}, launching);
        next[app.key] = {
            count: app.allWindows.length + app.minimized.length,
            until: Date.now() + launchTimeout
        };
        launching = next;
        rebuild();
    }

    function openLauncher() {
        run(["wofi", "--show", "drun"]);
    }

    // `workspaceId` is the one in front of the dock, where a minimized window
    // comes back to.
    function activate(app, workspaceId) {
        if (app.windows.length === 0) {
            if (app.minimized.length > 0)
                Hypr.restoreWindow(app.minimized[0].address, workspaceId);
            else
                launch(app);
            return;
        }
        const addresses = app.windows.map(w => w.address);   // stable: oldest first
        const i = addresses.indexOf(Hypr.activeAddress);
        if (i >= 0) {
            if (addresses.length > 1)
                Hypr.focusWindow(addresses[(i + 1) % addresses.length]);
        } else {
            const recent = app.windows.slice().sort((a, b) =>
                (a.focusHistoryID ?? 1e9) - (b.focusHistoryID ?? 1e9));
            Hypr.focusWindow(recent[0].address);
        }
    }

    // A drag in the dock: `key` to position `index` among the pinned apps the
    // dock shows (`shown`, in order). Pins the dock is not showing, because
    // their desktop file is gone, keep their place at the end.
    function pinAt(key, index, shown) {
        const visible = shown.filter(k => k !== key);
        index = Math.max(0, Math.min(index, visible.length));
        visible.splice(index, 0, key);
        savePinned(visible.concat(pinned.filter(k => visible.indexOf(k) < 0)));
    }

    function pin(key) {
        if (pinned.indexOf(key) < 0)
            savePinned(pinned.concat([key]));
    }

    function unpin(key) {
        if (pinned.indexOf(key) >= 0) {
            order = order.concat([key]);   // still open, it stays, after the pins
            savePinned(pinned.filter(k => k !== key));
        }
    }

    function closeAll(app) {
        for (const w of app.windows)
            Hypr.closeWindow(w.address);
    }
}
