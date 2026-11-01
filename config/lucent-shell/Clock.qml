// The time; click for the full date and seconds. Hover for a month's calendar
// with ISO week numbers, and scroll over it to page through the months.
// Calendar colours are waybar's: month mauve, weekdays peach, weeks sapphire,
// today red and underlined — from the palette, so they follow the theme
// without theme.sh patching anything.

import QtQuick
import Quickshell

Pill {
    id: clock

    // The panel has room for the date, and its clock is the only one.
    property bool withDate: Settings.panelMode
    property bool full: false
    property int monthOffset: 0

    SystemClock {
        id: now
        precision: clock.full ? SystemClock.Seconds : SystemClock.Minutes
    }

    text: Qt.formatDateTime(now.date,
        full ? "dddd, dd MMMM yyyy  ·  HH:mm:ss"
             : withDate ? "ddd dd MMM  HH:mm" : "HH:mm")
    fg: Theme.c("lavender")
    fontWeight: Font.Bold
    richTip: true
    tip: calendar(now.date, monthOffset)

    onClicked: button => {
        if (button === Qt.LeftButton)
            full = !full;
        else if (button === Qt.RightButton)
            monthOffset = 0;
    }
    onScrolled: step => monthOffset -= step
    onHoveredChanged: if (!hovered) monthOffset = 0

    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - yearStart) / 86400000 + 1) / 7);
    }

    function span(color, text, bold, underline) {
        let s = text;
        if (underline) s = "<u>" + s + "</u>";
        if (bold) s = "<b>" + s + "</b>";
        return "<font color='" + Theme.palette[color] + "'>" + s + "</font>";
    }

    function calendar(today, offset) {
        const locale = Qt.locale();
        const first = new Date(today.getFullYear(), today.getMonth() + offset, 1);
        const year = first.getFullYear(), month = first.getMonth();
        const days = new Date(year, month + 1, 0).getDate();
        // Qt counts Monday as 1 and Sunday as 7; Date counts Sunday as 0.
        const weekStart = locale.firstDayOfWeek % 7;
        const lead = (first.getDay() - weekStart + 7) % 7;

        const cell = s => "<td align='right'>&nbsp;" + s + "</td>";
        let html = "<table cellspacing='0' cellpadding='1' style='font-family: monospace'>";
        html += "<tr><td colspan='8' align='center'>"
              + span("mauve", locale.standaloneMonthName(month, Locale.LongFormat) + " " + year, true)
              + "</td></tr><tr>";
        for (let i = 0; i < 7; i++) {
            const name = locale.dayName((weekStart + i) % 7, Locale.ShortFormat).slice(0, 2);
            html += cell(span("peach", name, true));
        }
        html += "<td></td></tr>";

        let day = 1 - lead;
        while (day <= days) {
            html += "<tr>";
            // The row's fourth day, which is ISO's own rule when weeks start
            // on Monday (the week holding Thursday), and keeps a Sunday-first
            // row from being named after the week its Sunday ends.
            const weekOf = new Date(year, month, day + 3);
            for (let i = 0; i < 7; i++, day++) {
                if (day < 1 || day > days) {
                    html += cell("&nbsp;&nbsp;");
                    continue;
                }
                const d = new Date(year, month, day);
                const isToday = d.toDateString() === today.toDateString();
                const label = (day < 10 ? "&nbsp;" : "") + day;
                html += cell(isToday ? span("red", label, true, true) : span("text", label));
            }
            html += cell(span("sapphire", "W" + isoWeek(weekOf), true)) + "</tr>";
        }
        return html + "</table>";
    }
}
