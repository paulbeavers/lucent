// Gone while Bluetooth is off or there is no adapter; the count of connected
// devices otherwise. Click for blueman.

import QtQuick
import Quickshell.Bluetooth

Pill {
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter !== null && adapter.enabled
    readonly property var connected: on ? adapter.devices.values.filter(d => d.connected) : []

    text: !on ? "" : connected.length > 0 ? "\u{f00b1} " + connected.length : "\u{f00af}"
    fg: Theme.c("blue")
    tip: !on ? "" : connected.length > 0 ? connected.map(d => d.name).join("\n") : adapter.name
    onClicked: Apps.run(["blueman-manager"])
}
