// Gone on a machine with no battery. Warning at 25%, critical at 10%, and a
// red pill when critical and not charging — waybar's states and style.

import QtQuick

Pill {
    readonly property int cap: Sys.battery
    readonly property bool charging: Sys.batteryStatus === "Charging"
    readonly property bool plugged: !charging && Sys.onMains
    readonly property bool critical: cap <= 10
    readonly property bool warning: cap <= 25
    readonly property var icons: ["\u{f007a}", "\u{f007d}", "\u{f007f}", "\u{f0081}", "\u{f0079}"]

    icon: !Sys.hasBattery ? ""
        : charging ? "\u{f0084}" : plugged ? "\uf1e6" : icons[Math.min(4, Math.floor(cap / 20))]
    text: Sys.hasBattery ? cap + "%" : ""
    fg: critical && !charging ? Theme.c("crust")
      : critical ? Theme.c("red") : warning ? Theme.c("peach") : Theme.c("green")
    bg: critical && !charging ? Theme.c("red") : "transparent"
    tip: Sys.batteryStatus
}
