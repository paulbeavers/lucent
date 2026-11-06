// The title of the window last focused on the workspace this monitor shows,
// so each screen names its own. Top bar only: in panel style the dock
// already shows what is open.

import QtQuick

Pill {
    id: title

    property var screen
    readonly property var window: Hypr.lastWindowOn(Hypr.activeWorkspaceOn(screen))
    readonly property int maxLength: 70

    // A glyph in place of the app's name for Firefox, Chromium and VS Code,
    // and before a terminal's title (one starting with ~). First match wins.
    function rewrite(t) {
        const rules = [
            [/^(.*) — Mozilla Firefox$/, "\u{f0239}  $1"],
            [/^(.*) - Chromium$/, "\uf268  $1"],
            [/^(.*) - Visual Studio Code$/, "\u{f0a1e}  $1"],
            [/^~(.*)$/, "\uf120  ~$1"]
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
