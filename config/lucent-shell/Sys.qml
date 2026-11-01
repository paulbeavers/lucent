pragma Singleton

// CPU, memory, temperature and battery, polled once for every bar on every
// screen. The figures come from scripts/stats.sh, every 3s: /proc and /sys
// reads, so this file only parses.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: sys

    property int cpu: 0                 // percent
    property real memTotal: 0           // kB
    property real memUsed: 0            // kB
    property int memPercent: 0
    property bool hasTemp: false
    property int tempC: 0
    property bool hasBattery: false
    property int battery: 0             // percent
    property string batteryStatus: ""   // Charging, Discharging, Full, Not charging
    property bool onMains: false

    property var lastCpu: null

    function parseStats(text) {
        let temp = false, bat = false, mains = false;
        for (const line of text.split("\n")) {
            const f = line.trim().split(/\s+/);
            if (f[0] === "cpu") {
                const v = f.slice(1).map(Number);
                const idle = v[3] + (v[4] || 0);
                const total = v.reduce((a, b) => a + b, 0);
                if (lastCpu) {
                    const dt = total - lastCpu.total;
                    sys.cpu = dt > 0 ? Math.round(100 * (1 - (idle - lastCpu.idle) / dt)) : 0;
                }
                lastCpu = { idle: idle, total: total };
            } else if (f[0] === "mem") {
                sys.memTotal = Number(f[1]);
                sys.memUsed = Number(f[1]) - Number(f[2]);
                sys.memPercent = sys.memTotal > 0 ? Math.round(100 * sys.memUsed / sys.memTotal) : 0;
            } else if (f[0] === "temp") {
                temp = true;
                sys.tempC = Math.round(Number(f[1]) / 1000);
            } else if (f[0] === "bat" && !bat) {
                bat = true;
                sys.battery = Number(f[1]);
                sys.batteryStatus = f.slice(2).join(" ");
            } else if (f[0] === "ac" && f[1] === "1") {
                mains = true;
            }
        }
        sys.hasTemp = temp;
        sys.hasBattery = bat;
        sys.onMains = mains;
    }

    Process {
        id: statsProc
        command: ["sh", Quickshell.shellPath("scripts/stats.sh")]
        stdout: StdioCollector {
            onStreamFinished: sys.parseStats(text)
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!statsProc.running) statsProc.running = true
    }
}
