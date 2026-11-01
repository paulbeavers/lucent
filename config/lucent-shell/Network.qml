// Wi-Fi signal, a wired link, or nothing, from NetworkManager. Click for
// nmtui in a floating terminal, as waybar's did.

import QtQuick

Pill {
    readonly property bool linked: Sys.netState.startsWith("connecting")
    readonly property bool down: Sys.netType === "" && !linked

    icon: down ? "\u{f05aa}"
        : Sys.netType === "wifi" ? "\uf1eb"
        : "\u{f0200}"
    text: down ? ""
        : linked ? "no IP"
        : Sys.netType === "wifi" ? Sys.netSignal + "%"
        : ""
    fg: down ? Theme.c("red") : Theme.c("green")
    tip: down ? "Disconnected"
        : (Sys.netType === "wifi" ? Sys.netSsid : Sys.netDevice) + "\n"
          + (Sys.netIp || "no address") + "\n"
          + "↓ " + Sys.bits(Sys.netDownBits) + "  ↑ " + Sys.bits(Sys.netUpBits)
    onClicked: Apps.run([Theme.config + "/hypr/scripts/terminal.sh", "--class", "floating-term", "-e", "nmtui"])
}
