// lucent-dock, drawn by Quickshell — the same dock as ../dock.py, in QML.
//
// Experimental, and chosen in ~/.config/lucent/dock-engine ("quickshell");
// dock.sh starts this with `qs -p` when that file says so and quickshell is
// installed, and the GTK dock otherwise. Behaviour matches dock.py:
//
//     left click     open the app, or focus its window; again cycles its windows
//     middle click   a new window
//     right click    its windows, New window, Pin / Unpin, Close
//
// The same files, so switching engines keeps everything:
//     ~/.config/lucent/dock-pinned     pinned desktop IDs, one per line
//     ~/.config/lucent/dock-mode       panel (default) or dock
//     ~/.config/lucent/dock-position   bottom (default) or top
//     ~/.config/waybar/colors.css      the palette theme.sh renders
//
// Things carried over from dock.py that are not visible here:
// - Hyprland is configured in Lua, so every dispatch is an hl.dsp call, sent
//   through hyprctl like the scripts send theirs.
// - Windows are read again (hyprctl -j clients) on window events, never on a
//   timer, and not while the menu is open.
// - GTK_THEME is worked out from colors.lua on every launch, or apps opened
//   from here keep the theme that was current when the dock started.
// - In panel mode the dock must be mapped after waybar's panel to sit on top
//   of it; waybar recreates its surface on every reload, so openlayer>>panel
//   maps the dock again.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    readonly property int iconSize: 40
    readonly property int maxDots: 3
    readonly property int panelHeight: 58          // waybar/panel.jsonc's height
    readonly property var defaultPinned: ["firefox.desktop", "thunar.desktop", "foot.desktop"]
    readonly property var events: ["openwindow", "closewindow", "activewindowv2",
                                   "movewindowv2", "windowtitlev2", "urgent"]

    readonly property string config: Quickshell.env("XDG_CONFIG_HOME")
                                     || Quickshell.env("HOME") + "/.config"

    // Read once: dock.sh restarts the dock when either changes.
    readonly property bool panelMode: modeFile.text().trim() !== "dock"
    readonly property string edge: positionFile.text().trim() === "top" ? "top" : "bottom"

    property var pinned: []
    property var order: []        // keys of unpinned running apps, first seen first
    property var apps: []         // what the dock shows, in order
    property var clients: []
    property string activeAddress: ""
    property bool menuOpen: false
    property bool clientsStale: false

    // ── palette ──────────────────────────────────────────────────────────────

    property var palette: ({
        base: "#1e1e2e", surface0: "#313244", surface1: "#45475a",
        subtext: "#a6adc8", text: "#cdd6f4", blue: "#89b4fa", red: "#f38ba8"
    })
    property string colorMode: "dark"

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    FileView {
        // theme.sh replaces this file by rename; watchChanges is meant to
        // follow that. If a theme switch ever leaves the dock in the old
        // colours, this is the first place to look (dock.py watches the
        // directory for exactly this reason).
        path: root.config + "/waybar/colors.css"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const next = Object.assign({}, root.palette);
            const re = /@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})/g;
            const css = text();
            let m;
            while ((m = re.exec(css)) !== null)
                next[m[1]] = m[2];
            root.palette = next;
        }
    }

    FileView {
        path: root.config + "/hypr/colors.lua"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = /\bmode\s*=\s*"(\w+)"/.exec(text());
            root.colorMode = m ? m[1] : "dark";
        }
    }

    function c(name) {
        return Qt.color(palette[name]);
    }

    // ── settings and pins ────────────────────────────────────────────────────

    FileView {
        id: modeFile
        path: root.config + "/lucent/dock-mode"       // panel unless "dock"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: positionFile
        path: root.config + "/lucent/dock-position"   // bottom unless "top"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: pinnedFile
        path: root.config + "/lucent/dock-pinned"
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: {
            root.pinned = text().split(/\s+/).filter(s => s.length > 0);
            root.rebuild();
        }
        onLoadFailed: {
            root.pinned = root.defaultPinned.slice();
            root.rebuild();
        }
    }

    function savePinned(ids) {
        pinned = ids;
        pinnedFile.setText(ids.map(i => i + "\n").join(""));
        rebuild();
    }

    // ── Hyprland ─────────────────────────────────────────────────────────────

    function luaString(s) {
        return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
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

    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    list = JSON.parse(text);
                } catch (e) {
                    list = [];
                }
                root.clients = list.filter(w =>
                    w.mapped !== false
                    && !String((w.workspace || {}).name || "").startsWith("special")
                    && (w.class || w.initialClass));
                const active = list.find(w => w.focusHistoryID === 0);
                root.activeAddress = active ? active.address : "";
                root.rebuild();
            }
        }
        onExited: {
            if (root.clientsStale) {
                root.clientsStale = false;
                running = true;
            }
        }
    }

    function readClients() {
        if (clientsProc.running)
            clientsStale = true;        // one more pass once this one is done
        else
            clientsProc.running = true;
    }

    // Events arrive in bursts (a window opening is four or five); one read
    // covers the lot.
    Timer {
        id: refreshTimer
        interval: 40
        onTriggered: {
            if (root.menuOpen)
                return;                 // the menu's closing calls it again
            root.readClients();
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.events.indexOf(event.name) >= 0)
                refreshTimer.restart();
            else if (event.name === "openlayer" && event.data === "panel")
                dock.raiseOverPanel();
        }
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.rebuild();
        }
    }

    // ── apps ─────────────────────────────────────────────────────────────────

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
        const keys = [];

        for (const id of pinned) {
            const entry = entryById(id);
            if (!entry)
                continue;
            byKey[id] = { key: id, entry: entry, cls: "", windows: [] };
        }

        const seen = order.slice();
        for (const w of clients) {
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
        for (const k of pinned)
            if (byKey[k])
                keys.push(k);
        for (const k of order)
            keys.push(k);

        apps = keys.map(k => {
            const a = byKey[k];
            return {
                key: a.key,
                entry: a.entry,
                name: a.entry ? a.entry.name : (a.cls || a.key),
                icon: iconSource(a.entry, a.cls),
                windows: a.windows,
                active: a.windows.some(w => w.address === activeAddress),
                urgent: a.windows.some(w => w.urgent),
                pinned: pinned.indexOf(a.key) >= 0
            };
        });
    }

    function gtkTheme() {
        return colorMode === "light" ? "Adwaita" : "Adwaita:dark";
    }

    function launch(app) {
        const entry = app.entry || entryById(app.key);
        if (!entry)
            return;
        let command = Array.from(entry.command);
        if (entry.runInTerminal)
            command = [config + "/hypr/scripts/terminal.sh"].concat(command);
        Quickshell.execDetached({
            command: command,
            workingDirectory: entry.workingDirectory || Quickshell.env("HOME"),
            environment: { GTK_THEME: gtkTheme() }
        });
    }

    function openLauncher() {
        Quickshell.execDetached({
            command: ["wofi", "--show", "drun"],
            environment: { GTK_THEME: gtkTheme() }
        });
    }

    function activateApp(app) {
        if (app.windows.length === 0) {
            launch(app);
            return;
        }
        const addresses = app.windows.map(w => w.address);   // stable: oldest first
        const i = addresses.indexOf(activeAddress);
        if (i >= 0) {
            if (addresses.length > 1)
                focusWindow(addresses[(i + 1) % addresses.length]);
        } else {
            // Most recently focused first; Hyprland counts focusHistoryID from 0.
            const recent = app.windows.slice().sort((a, b) =>
                (a.focusHistoryID ?? 1e9) - (b.focusHistoryID ?? 1e9));
            focusWindow(recent[0].address);
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
            closeWindow(w.address);
    }

    Component.onCompleted: readClients()

    // ── the dock ─────────────────────────────────────────────────────────────

    PanelWindow {
        id: dock

        WlrLayershell.namespace: "lucent-dock"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors.bottom: root.edge === "bottom"
        anchors.top: root.edge === "top"
        margins.bottom: root.panelMode ? 0 : 6
        margins.top: root.panelMode ? 0 : 6

        // Inside the panel waybar reserves the space, so the dock takes none
        // and ignores waybar's, or Hyprland would stack it above the panel.
        exclusionMode: root.panelMode ? ExclusionMode.Ignore : ExclusionMode.Auto

        color: "transparent"
        implicitWidth: slab.width
        implicitHeight: root.panelMode ? root.panelHeight : slab.height

        // Surfaces on one layer stack in the order they map, so a panel that
        // waybar has just recreated covers the dock. Mapping again fixes it.
        function raiseOverPanel() {
            if (!root.panelMode || !visible)
                return;
            visible = false;
            visible = true;
        }

        Rectangle {
            id: slab
            anchors.centerIn: parent
            width: row.implicitWidth + (root.panelMode ? 8 : 16)
            height: row.implicitHeight + (root.panelMode ? 0 : 8)
            radius: root.panelMode ? 0 : 14
            color: root.panelMode ? "transparent" : root.alpha(root.c("base"), 0.85)
            border.width: root.panelMode ? 0 : 2
            border.color: root.alpha(root.c("surface1"), 0.9)

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 2

                Repeater {
                    model: root.apps
                    delegate: DockButton {
                        required property var modelData
                        app: modelData
                    }
                }

                Item {
                    width: 14
                    height: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        anchors.centerIn: parent
                        width: 2
                        height: parent.height - 8
                        color: root.alpha(root.c("surface1"), 0.9)
                    }
                }

                LauncherButton {}
            }
        }
    }

    // One icon: pinned or running, with a dot per window.
    component DockButton: Rectangle {
        id: button
        property var app

        width: root.iconSize + 10
        height: root.iconSize + 4 + 2 + 4
        radius: 10
        color: app.active ? root.alpha(root.c("surface1"), 0.9)
             : mouse.containsMouse ? root.alpha(root.c("surface1"), 0.7)
             : "transparent"

        Column {
            anchors.centerIn: parent
            spacing: 2

            // The dots sit between the icon and the screen edge, as on a Mac.
            Dots { visible: root.edge === "top"; app: button.app }
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.iconSize
                height: root.iconSize
                // Logical size; Qt asks the icon for size × the output's
                // scale, which is what keeps it sharp at 1.33.
                sourceSize.width: root.iconSize
                sourceSize.height: root.iconSize
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                source: button.app.icon
            }
            Dots { visible: root.edge === "bottom"; app: button.app }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onClicked: event => {
                tooltip.hide();
                if (event.button === Qt.LeftButton)
                    root.activateApp(button.app);
                else if (event.button === Qt.MiddleButton)
                    root.launch(button.app);
                else
                    menu.openFor(button, button.app);
            }
            onContainsMouseChanged: containsMouse ? tooltip.showFor(button, button.app.name)
                                                  : tooltip.hide()
        }
    }

    component Dots: Row {
        property var app
        anchors.horizontalCenter: parent.horizontalCenter
        height: 4
        spacing: 3
        Repeater {
            model: Math.min(app.windows.length, root.maxDots)
            delegate: Rectangle {
                width: 4
                height: 4
                radius: 2
                color: app.urgent ? root.c("red")
                     : app.active ? root.c("blue")
                     : root.c("subtext")
            }
        }
    }

    // All apps: a 3×3 grid drawn here rather than a symbolic icon, which
    // Quickshell would not recolour to the theme.
    component LauncherButton: Rectangle {
        width: root.iconSize + 10
        height: root.iconSize + 10
        anchors.verticalCenter: parent.verticalCenter
        radius: 10
        color: launcherMouse.containsMouse ? root.alpha(root.c("surface1"), 0.7) : "transparent"

        Grid {
            anchors.centerIn: parent
            columns: 3
            spacing: 4
            Repeater {
                model: 9
                delegate: Rectangle {
                    width: 6
                    height: 6
                    radius: 1.5
                    color: launcherMouse.containsMouse ? root.c("text") : root.c("subtext")
                }
            }
        }

        MouseArea {
            id: launcherMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                tooltip.hide();
                root.openLauncher();
            }
            onContainsMouseChanged: containsMouse ? tooltip.showFor(parent, "All apps")
                                                  : tooltip.hide()
        }
    }

    // ── tooltip ──────────────────────────────────────────────────────────────

    PopupWindow {
        id: tooltip
        property string label: ""
        property Item target: null

        function showFor(item, text) {
            if (root.menuOpen)
                return;
            target = item;
            label = text;
            tooltipDelay.restart();
        }
        function hide() {
            tooltipDelay.stop();
            visible = false;
        }

        anchor.window: dock
        anchor.item: target
        anchor.edges: root.edge === "top" ? Edges.Bottom : Edges.Top
        anchor.gravity: root.edge === "top" ? Edges.Bottom : Edges.Top
        anchor.adjustment: PopupAdjustment.Slide
        color: "transparent"
        implicitWidth: tipText.implicitWidth + 16
        implicitHeight: tipText.implicitHeight + 10

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: root.c("base")
            border.width: 1
            border.color: root.c("surface1")
            Text {
                id: tipText
                anchors.centerIn: parent
                text: tooltip.label
                color: root.c("text")
            }
        }

        Timer {
            id: tooltipDelay
            interval: 500
            onTriggered: if (tooltip.target) tooltip.visible = true
        }
    }

    // ── the right-click menu ─────────────────────────────────────────────────

    PopupWindow {
        id: menu
        property var app: null
        property var items: []
        property Item target: null
        property real menuWidth: 160

        TextMetrics {
            id: metrics
        }

        function openFor(item, a) {
            const list = [];
            for (const w of a.windows) {
                let title = (w.title || a.name).trim();
                if (title.length > 48)
                    title = title.slice(0, 47) + "…";
                list.push({ label: title, run: () => root.focusWindow(w.address) });
            }
            if (list.length)
                list.push({ separator: true });
            if (a.entry) {
                list.push({ label: "New window", run: () => root.launch(a) });
                list.push(a.pinned
                    ? { label: "Unpin from dock", run: () => root.unpin(a.key) }
                    : { label: "Pin to dock", run: () => root.pin(a.key) });
            }
            if (a.windows.length) {
                list.push({ separator: true });
                list.push({
                    label: a.windows.length === 1 ? "Close window"
                         : "Close all " + a.windows.length + " windows",
                    run: () => root.closeAll(a)
                });
            }
            let widest = 160;
            for (const it of list) {
                if (it.separator)
                    continue;
                metrics.text = it.label;
                widest = Math.max(widest, Math.ceil(metrics.advanceWidth) + 20);
            }
            menuWidth = widest;
            app = a;
            items = list;
            target = item;
            root.menuOpen = true;
            visible = true;
        }

        function dismiss() {
            visible = false;
        }

        onVisibleChanged: {
            if (!visible) {
                root.menuOpen = false;
                refreshTimer.restart();
            }
        }

        // Away from the screen edge the dock is on.
        anchor.window: dock
        anchor.item: target
        anchor.edges: root.edge === "top" ? Edges.Bottom : Edges.Top
        anchor.gravity: root.edge === "top" ? Edges.Bottom : Edges.Top
        anchor.adjustment: PopupAdjustment.Slide
        color: "transparent"
        implicitWidth: menu.menuWidth + 12
        implicitHeight: menuColumn.implicitHeight + 12

        // A click anywhere outside the menu closes it.
        HyprlandFocusGrab {
            windows: [menu]
            active: menu.visible
            onCleared: menu.dismiss()
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: root.c("base")
            border.width: 2
            border.color: root.c("surface1")

            Column {
                id: menuColumn
                anchors.centerIn: parent
                width: menu.menuWidth

                Repeater {
                    model: menu.items
                    delegate: Item {
                        required property var modelData
                        width: menuColumn.width
                        height: modelData.separator ? 7 : itemText.implicitHeight + 8

                        Rectangle {
                            visible: modelData.separator === true
                            anchors.centerIn: parent
                            width: parent.width - 8
                            height: 1
                            color: root.c("surface1")
                        }

                        Rectangle {
                            visible: !modelData.separator
                            anchors.fill: parent
                            radius: 8
                            color: itemMouse.containsMouse ? root.c("surface0") : "transparent"

                            Text {
                                id: itemText
                                anchors.verticalCenter: parent.verticalCenter
                                x: 10
                                text: modelData.label || ""
                                color: root.c("text")
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    const run = modelData.run;
                                    menu.dismiss();
                                    run();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
