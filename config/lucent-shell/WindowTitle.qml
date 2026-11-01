// The focused window's title, on the monitor it is on — waybar's
// hyprland/window with separate-outputs. Top bar only: in panel style the
// dock already shows what is open.

import QtQuick

Pill {
    id: title

    property var screen
    readonly property var window: Hypr.lastWindowOn(Hypr.activeWorkspaceOn(screen))
    readonly property int maxLength: 70

    // waybar's rewrite rules, in the same order.
    function rewrite(t) {
        const rules = [
            [/^(.*) — Mozilla Firefox$/, "\u{f0239}  $1"],
            [/^(.*) - Chromium$/, "  $1"],
            [/^(.*) - Visual Studio Code$/, "\u{f0a1e}  $1"],
            [/^~(.*)$/, "  ~$1"]
        ];
        for (const [re, to] of rules)
            if (re.test(t))
                return t.replace(re, to);
        return t;
    }

    text: {
        const t = window ? rewrite(String(window.title || "").trim()) : "";
        return t.length > maxLength ? t.slice(0, maxLength - 1) + "…" : t;
    }
    fg: Theme.c("subtext")
    fontWeight: Font.Medium
}
