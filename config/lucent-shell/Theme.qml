pragma Singleton

// The palette and font, from the files theme.sh renders for waybar: the same
// colors.css the GTK dock and lucent-config read, and font.css. Both are
// watched, so a theme switch recolours the shell without a restart.
//
// theme.sh replaces these files by rename. FileView's watch is expected to
// follow that; dock.py watches the directory instead for exactly this
// reason, so if a theme switch ever leaves the shell in the old colours,
// look here first.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: theme

    readonly property string config: Quickshell.env("XDG_CONFIG_HOME")
                                     || Quickshell.env("HOME") + "/.config"

    // Catppuccin Mocha, for the moment before colors.css has been read.
    property var palette: ({
        crust: "#11111b", mantle: "#181825", base: "#1e1e2e",
        surface0: "#313244", surface1: "#45475a", overlay: "#7f849c",
        subtext: "#a6adc8", text: "#cdd6f4", rosewater: "#f5e0dc",
        red: "#f38ba8", peach: "#fab387", yellow: "#f9e2af", green: "#a6e3a1",
        teal: "#94e2d5", sapphire: "#74c7ec", blue: "#89b4fa",
        lavender: "#b4befe", mauve: "#cba6f7", pink: "#f5c2e7"
    })
    property string mode: "dark"
    property string font: "JetBrainsMono Nerd Font"

    function c(name) {
        return Qt.color(palette[name] || "#ff00ff");
    }

    function alpha(name, a) {
        const k = c(name);
        return Qt.rgba(k.r, k.g, k.b, a);
    }

    // GTK_THEME for apps started from the shell, worked out at launch time:
    // the shell keeps the environment it started with, so after a switch from
    // dark to light everything it opened would come up dark until the next
    // login. env.lua sets the same thing for Hyprland.
    function gtkTheme() {
        return mode === "light" ? "Adwaita" : "Adwaita:dark";
    }

    FileView {
        path: theme.config + "/waybar/colors.css"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const css = text();
            const next = Object.assign({}, theme.palette);
            const re = /@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})/g;
            let m;
            while ((m = re.exec(css)) !== null)
                next[m[1]] = m[2];
            theme.palette = next;
        }
    }

    FileView {
        path: theme.config + "/hypr/colors.lua"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const m = /\bmode\s*=\s*"(\w+)"/.exec(text());
            theme.mode = m ? m[1] : "dark";
        }
    }

    FileView {
        path: theme.config + "/waybar/font.css"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const m = /font-family:\s*"([^"]+)"/.exec(text());
            if (m)
                theme.font = m[1];
        }
    }
}
