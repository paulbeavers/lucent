// Red while something records the screen or the microphone: a PipeWire
// stream capturing video or audio. The tooltip says which apps.

import QtQuick
import Quickshell.Services.Pipewire

Pill {
    id: privacy

    readonly property var nodes: Pipewire.nodes.values
    readonly property var video: nodes.filter(n => n.isStream && (n.properties || {})["media.class"] === "Stream/Input/Video")
    readonly property var audioIn: nodes.filter(n => n.isStream && (n.properties || {})["media.class"] === "Stream/Input/Audio")

    function names(list) {
        return list.map(n => (n.properties || {})["application.name"] || n.name).join(", ");
    }

    PwObjectTracker {
        objects: privacy.nodes.filter(n => n.isStream)
    }

    text: [video.length ? "\u{f0379}" : "", audioIn.length ? "\u{f036c}" : ""]
          .filter(s => s).join("  ")
    fg: Theme.c("red")
    tip: [video.length ? "Screen or camera: " + names(video) : "",
          audioIn.length ? "Microphone: " + names(audioIn) : ""].filter(s => s).join("\n")
}
