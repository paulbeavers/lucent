pragma Singleton

// The dock's model: one entry per app, not per window — the pinned apps
// first, then anything else open, in the order first seen.
//
// Pins are ~/.config/lucent/dock-pinned, one desktop file ID per line, the
// same file the GTK dock reads, so switching engines keeps them.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: apps

    readonly property var defaultPinned: ["firefox.desktop", "thunar.desktop", "foot.desktop"]

    property var pinned: []
    property var order: []        // keys of unpinned running apps, first seen first
    property var list: []         // what the dock shows, in order

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

    function entryById(id) {
        return DesktopEntries.byId(id.replace(/\.desktop$/, ""));
    }

    function iconSource(entry, cls) {
        const name = entry && entry.icon ? entry.icon : (cls || "").toLowerCase();
        if (name.startsWith("/"))
            return "file://" + name;
        return Quickshell.iconPath(name, "application-x-executable");
    }

    function rebuild() {
        const byKey = {};
        for (const id of pinned) {
            const entry = entryById(id);
            if (entry)
                byKey[id] = { key: id, entry: entry, cls: "", windows: [] };
        }

        const seen = order.slice();
        for (const w of Hypr.clients) {
            const cls = w.class || w.initialClass;
            const entry = DesktopEntries.heuristicLookup(cls);
            const key = entry ? entry.id + ".desktop" : "class:" + cls.toLowerCase();
            if (!byKey[key]) {
                byKey[key] = { key: key, entry: entry, cls: cls, windows: [] };
                if (seen.indexOf(key) < 0 && pinned.indexOf(key) < 0)
                    seen.push(key);
            }
            byKey[key].cls = byKey[key].cls || cls;
            byKey[key].windows.push(w);
        }

        order = seen.filter(k => byKey[k] && pinned.indexOf(k) < 0);
        const keys = pinned.filter(k => byKey[k]).concat(order);

        list = keys.map(k => {
            const a = byKey[k];
            return {
                key: a.key,
                entry: a.entry,
                name: a.entry ? a.entry.name : (a.cls || a.key),
                icon: iconSource(a.entry, a.cls),
                windows: a.windows,
                active: a.windows.some(w => w.address === Hypr.activeAddress),
                urgent: a.windows.some(w => w.urgent),
                pinned: pinned.indexOf(a.key) >= 0
            };
        });
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

    // A shell command line, for the bar's click actions.
    function sh(line) {
        run(["sh", "-c", line]);
    }

    function launch(app) {
        const entry = app.entry || entryById(app.key);
        if (!entry)
            return;
        let command = Array.from(entry.command);
        if (entry.runInTerminal)
            command = [Theme.config + "/hypr/scripts/terminal.sh"].concat(command);
        run(command, entry.workingDirectory);
    }

    function openLauncher() {
        run(["wofi", "--show", "drun"]);
    }

    function activate(app) {
        if (app.windows.length === 0) {
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
