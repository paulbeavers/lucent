// The default output's volume, through PipeWire. Scroll for ±5%, click for
// pavucontrol, right-click to mute — waybar's pulseaudio module.

import QtQuick
import Quickshell.Services.Pipewire

Pill {
    id: audio

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.audio !== null
    readonly property int volume: ready ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool muted: ready && sink.audio.muted
    readonly property bool bluetooth: ready && String(sink.name).startsWith("bluez")

    // Properties and volume are only filled in for a node something tracks.
    PwObjectTracker {
        objects: audio.sink ? [audio.sink] : []
    }

    icon: !ready ? ""
        : muted ? "\u{f075f}"
        : bluetooth ? "\u{f00b0}" : volume < 34 ? "\u{f057f}" : volume < 67 ? "\u{f0580}" : "\u{f057e}"
    text: !ready ? "" : muted ? "muted" : volume + "%"
    fg: muted ? Theme.c("red") : Theme.c("sapphire")
    tip: ready ? (sink.description || sink.name) + " — " + volume + "%" : ""

    onClicked: button => {
        if (button === Qt.LeftButton)
            Apps.run(["pavucontrol"]);
        else if (button === Qt.RightButton && ready)
            sink.audio.muted = !sink.audio.muted;
    }
    onScrolled: step => {
        if (ready)
            sink.audio.volume = Math.max(0, Math.min(1, (volume + 5 * step) / 100));
    }
}
