pragma Singleton

// CPU, memory, temperature, battery and network, polled once for every bar on
// every screen. The figures come from scripts/stats.sh (every 3s: /proc and
// /sys reads) and scripts/net.sh (every 5s: nmcli), so this file only parses.

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

    property string netType: ""         // wifi, ethernet, or "" when disconnected
    property string netState: "disconnected"
    property string netDevice: ""
    property string netSsid: ""
    property int netSignal: 0
    property string netIp: ""
    property real netDownBits: 0        // per second
    property real netUpBits: 0

    property var lastCpu: null
    property var lastNet: null

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

    function parseNet(text) {
        const kv = {};
        for (const line of text.split("\n")) {
            const i = line.indexOf("=");
            if (i > 0)
                kv[line.slice(0, i)] = line.slice(i + 1);
        }
        sys.netState = kv.state || "disconnected";
        sys.netType = sys.netState.startsWith("connect") ? (kv.type || "") : "";
        sys.netDevice = kv.dev || "";
        sys.netSsid = kv.ssid || "";
        sys.netSignal = Number(kv.signal || 0);
        sys.netIp = kv.ip || "";
        const now = Date.now();
        const rx = Number(kv.rx || 0), tx = Number(kv.tx || 0);
        if (lastNet && lastNet.dev === sys.netDevice && now > lastNet.time) {
            const s = (now - lastNet.time) / 1000;
            sys.netDownBits = Math.max(0, (rx - lastNet.rx) * 8 / s);
            sys.netUpBits = Math.max(0, (tx - lastNet.tx) * 8 / s);
        } else {
            sys.netDownBits = 0;
            sys.netUpBits = 0;
        }
        lastNet = { dev: sys.netDevice, rx: rx, tx: tx, time: now };
    }

    // 1.2Mb/s, as waybar's {bandwidthDownBits} printed it.
    function bits(n) {
        const units = ["b/s", "kb/s", "Mb/s", "Gb/s"];
        let i = 0;
        while (n >= 1000 && i < units.length - 1) {
            n /= 1000;
            i++;
        }
        return (i === 0 ? Math.round(n) : n.toFixed(1)) + units[i];
    }

    Process {
        id: statsProc
        command: ["sh", Quickshell.shellPath("scripts/stats.sh")]
        stdout: StdioCollector {
            onStreamFinished: sys.parseStats(text)
        }
    }

    Process {
        id: netProc
        command: ["sh", Quickshell.shellPath("scripts/net.sh")]
        stdout: StdioCollector {
            onStreamFinished: sys.parseNet(text)
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!statsProc.running) statsProc.running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!netProc.running) netProc.running = true
    }
}
