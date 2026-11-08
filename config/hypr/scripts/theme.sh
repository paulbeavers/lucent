#!/usr/bin/env bash
# Colour theme picker — SUPER + SHIFT + T. Uses wofi so it matches the launcher.
#
#     theme.sh                  open the picker
#     theme.sh --set <slug>     apply a theme by filename, e.g. nord
#     theme.sh --list           slug and display name, one per line
#     theme.sh --current        slug of the theme in effect
#     theme.sh --no-reload      skip signalling the running apps (install time)
#     theme.sh --firefox        the current theme into Firefox's profiles only
#
# A theme is 19 colour roles in ~/.config/hypr/themes/<slug>.theme. Applying one
# renders those roles into whatever form each app understands:
#
#   hypr/colors.lua     role = "hex" table   required by theme.lua
#   lucent/colors.css   @define-color        read by the shell and lucent-config
#   lucent/font.css     font-family          read by the shell and lucent-config
#   foot/colors.ini     key=hex              included by foot.ini
#   mako/colors         key=#hex + sections  included by mako/config
#   gtk-3.0/lucent.css  GTK 3 widget rules   @imported by gtk-3.0/gtk.css
#   gtk-4.0/lucent.css  libadwaita variables @imported by gtk-4.0/gtk.css
#   <firefox profile>/chrome/lucent.css      @imported by userChrome.css
#
# A theme may also name fonts and an icon theme, for a look that is more than
# colour (adwaita-light is GNOME's):
#
#   font  = Adwaita Sans    the bar, launcher, notifications, lock screen,
#                           window groups and GTK apps
#   mono  = Adwaita Mono    the terminal and GTK's monospace
#   icons = Adwaita         GTK's icon theme
#
# Each is optional, and a theme without one gets lucent's own: JetBrainsMono
# Nerd Font in lucent's pieces, Noto Sans in GTK apps, Papirus icons.
#
# And the border of windows without focus, which is otherwise surface0:
#
#   border = 6e6e6e         Hyprland's inactive window and group borders
#
# surface0 is also every separator, GTK border and hover background, so a
# theme that wants a stronger window outline sets this rather than darkening
# surface0 everywhere.
#
# And the terminal's palette, which can come from another theme:
#
#   terminal = catppuccin-mocha-blue-contrast
#
# foot then takes that theme's colours and mode, so a light desktop can keep a
# dark terminal. Its font stays this theme's mono.
#
#   terminal_alpha = 0.98
#
# foot's opacity, 0 to 1, in place of the default: 1.0 under a light palette,
# 0.95 under a dark one.
#
# Two configs are patched in place instead of getting their own file:
#
#   wofi/style.css       wofi hands GTK the stylesheet as a string rather than
#                        a path, so a relative @import resolves against the
#                        working directory the launcher was started from. The
#                        colours are written between markers in style.css.
#   hyprlock.conf        deliberately not on an include: a mistake there locks
#                        you out, and there is no way to dry-run its config.
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
THEME_DIR="${THEME_DIR:-$CFG/hypr/themes}"
ACTIVE_FILE="$CFG/hypr/.active-theme"
RELOAD=1

# Sentinels around the generated block in wofi/style.css. Matched by grep and
# sed, so keep them free of regex metacharacters.
WOFI_MARK_BEGIN="theme colours begin"
WOFI_MARK_END="theme colours end"

# What a theme without font, mono or icons gets.
DEFAULT_FONT="JetBrainsMono Nerd Font"
DEFAULT_GTK_FONT="Noto Sans"

note() { command -v notify-send >/dev/null && notify-send -a Theme "$@" || true; }

die() {
    printf 'theme.sh: %s\n' "$1" >&2
    note "Theme" "$1"
    exit 1
}

declare -A C=()

# `key = value`, ignoring comments and blanks. Values are bare six-digit hex so
# each renderer can prefix them the way its own format wants.
load_theme() {
    local file="$1" key val
    [[ -f $file ]] || die "no such theme: $file"
    C=()
    while IFS= read -r line; do
        line="${line%%#*}"
        [[ $line == *=* ]] || continue
        key="${line%%=*}"; val="${line#*=}"
        key="${key//[[:space:]]/}"
        # Trim the ends only. Stripping every space would turn a display name
        # like "Catppuccin Mocha" into "CatppuccinMocha".
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        [[ -n $key && -n $val ]] && C["$key"]="$val"
    done < "$file"
    local role
    for role in crust mantle base surface0 surface1 overlay subtext text \
                rosewater red peach yellow green teal sapphire blue \
                lavender mauve pink; do
        [[ -n ${C[$role]:-} ]] || die "$file is missing the '$role' colour"
    done
}

# Write to a temp file in the same directory and move it into place, so a
# failure part-way through cannot leave an app reading half a config.
emit() {
    local dest="$1" tmp
    mkdir -p "${dest%/*}"
    tmp="$(mktemp "${dest}.XXXXXX")"
    cat > "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" "$dest"
}

# Hyprland's config is Lua as of 0.55 (.conf is removed in 0.57), so the
# palette is a module returning a table. theme.lua does `require("colors")`
# and wraps each value in rgb(...) itself.
render_hypr() {
    {
        echo "-- Generated by theme.sh — edits here are overwritten."
        echo "-- Active theme: ${C[name]:-unknown}"
        echo "return {"
        local role
        for role in crust mantle base surface0 surface1 overlay subtext text \
                    rosewater red peach yellow green teal sapphire blue \
                    lavender mauve pink; do
            printf '    %-9s = "%s",\n' "$role" "${C[$role]}"
        done
        # Not a colour: env.lua reads it to set GTK_THEME at login.
        printf '    %-9s = "%s",\n' mode "${C[mode]:-dark}"
        # Nor this: theme.lua's window-group bar is text.
        printf '    %-9s = "%s",\n' font "${C[font]:-$DEFAULT_FONT}"
        # The inactive window border, surface0 unless the theme says otherwise.
        printf '    %-9s = "%s",\n' border "${C[border]:-${C[surface0]}}"
        echo "}"
    } | emit "$CFG/hypr/colors.lua"
}

# GTK and the portal follow the theme's mode. color-scheme is what Firefox and
# every portal-aware app read, and they change live; gtk-theme and icon-theme
# are what GTK 3 reads. Without a session bus — install time, in a chroot —
# gsettings fails and the system dconf defaults install.sh writes stay in
# charge, which are dark like the default theme.
set_gtk_mode() {
    command -v gsettings >/dev/null || return 0
    local k=org.gnome.desktop.interface
    if [[ ${C[mode]:-dark} == light ]]; then
        # prefer-light is GNOME 47's; older schemas only know default.
        gsettings set $k color-scheme prefer-light 2>/dev/null ||
            gsettings set $k color-scheme default 2>/dev/null || true
        gsettings set $k gtk-theme  Adwaita       2>/dev/null || true
        gsettings set $k icon-theme "${C[icons]:-Papirus-Light}" 2>/dev/null || true
    else
        gsettings set $k color-scheme prefer-dark  2>/dev/null || true
        gsettings set $k gtk-theme  Adwaita-dark  2>/dev/null || true
        gsettings set $k icon-theme "${C[icons]:-Papirus-Dark}" 2>/dev/null || true
    fi
    set_gtk_fonts
}

# The family follows the theme and the size stays what it was, because the
# size is lucent-config's Look page's ("Interface font size"). A theme with no
# mono gives monospace back to the system default.
set_gtk_fonts() {
    local k=org.gnome.desktop.interface cur size
    cur="$(gsettings get $k font-name 2>/dev/null)" || return 0
    cur="${cur//\'/}"
    size="${cur##* }"
    [[ $size =~ ^[0-9]+([.][0-9]+)?$ ]] || size=11
    gsettings set $k font-name "${C[font]:-$DEFAULT_GTK_FONT} $size" 2>/dev/null || true
    if [[ -n ${C[mono]:-} ]]; then
        cur="$(gsettings get $k monospace-font-name 2>/dev/null)"
        cur="${cur//\'/}"
        size="${cur##* }"
        [[ $size =~ ^[0-9]+([.][0-9]+)?$ ]] || size=11
        gsettings set $k monospace-font-name "${C[mono]} $size" 2>/dev/null || true
    else
        gsettings reset $k monospace-font-name 2>/dev/null || true
    fi
}

# The font, in its own file beside colors.css, so lucent-config can take the
# palette without the font: it keeps its monospace look unless a theme names a
# font. The symbol fonts stay in the list behind the theme's, for the bar's icons.
render_font_css() {
    {
        echo "/* Generated by theme.sh — edits here are overwritten."
        echo "   Active theme: ${C[name]:-unknown} */"
        echo "* {"
        printf '  font-family: "%s", "Symbols Nerd Font", "Font Awesome 6 Free", sans-serif;\n' \
            "${C[font]:-$DEFAULT_FONT}"
        echo "}"
    } | emit "$CFG/lucent/font.css"
}

define_colors() {
    local role
    for role in crust mantle base surface0 surface1 overlay subtext text \
                rosewater red peach yellow green teal sapphire blue \
                lavender mauve pink; do
        printf '@define-color %-9s #%s;\n' "$role" "${C[$role]}"
    done
}

# The palette as GTK @define-color lines. The shell parses the same lines.
render_gtk_css() {
    local dest="$1"
    {
        echo "/* Generated by theme.sh — edits here are overwritten."
        echo "   Active theme: ${C[name]:-unknown} */"
        define_colors
    } | emit "$dest"
}

# GTK apps get stock Adwaita or Adwaita-dark from set_gtk_mode; this puts the
# palette on them. Two files, because the two toolkits take colour differently:
#
#   gtk-3.0/lucent.css  GTK 3's Adwaita writes literal colours into its widget
#                       rules, so redefining its named colours (@theme_bg_color)
#                       changes next to nothing. These are explicit rules for
#                       the widgets: windows, views, sidebars, toolbars,
#                       entries, buttons, checks, switches, sliders, tabs,
#                       scrollbars, menus, popovers, tooltips.
#   gtk-4.0/lucent.css  libadwaita (1.6 and later) reads its colours from CSS
#                       variables, so libadwaita apps — file-roller — follow
#                       from a handful of them. Plain GTK 4 apps (pavucontrol)
#                       stay stock: rules for them would land on lucent-config
#                       and on libadwaita's own widgets too, and there is no
#                       selector that tells them apart.
#
# Every GTK 3 toplevel — window, dialog, message dialog, menu, tooltip — has
# the style class "background", so the rules hang off that, minus the GTK 3
# window that is already themed and must be left alone: wofi's (#window), whose
# own stylesheet would otherwise be overridden.
#
# Each file is @imported by its toolkit's gtk.css, one line added at the top if
# missing, so a hand-written gtk.css is never overwritten. GTK rereads them
# when the GTK theme changes: a switch between a dark and a light theme
# recolours open windows; between two dark ones, windows opened after the
# switch have the new colours.
render_gtk_user_css() {
    local P='.background:not(#window)'
    {
        echo "/* Generated by theme.sh — edits here are overwritten."
        echo "   Active theme: ${C[name]:-unknown}"
        echo "   Imported by gtk.css; see theme.sh's render_gtk_user_css. */"
        gtk_named_colors
        cat <<CSS

/* ── windows and their parts ─────────────────────────────────────────────── */
${P} {
  background-color: @lucent_base;
  color: @lucent_text;
}

${P} headerbar,
${P} .titlebar,
${P} menubar,
${P} toolbar,
${P} .toolbar,
${P} .inline-toolbar,
${P} statusbar,
${P} .statusbar,
${P} actionbar,
${P} searchbar {
  background-color: @lucent_mantle;
  background-image: none;
  color: @lucent_text;
  border-color: @lucent_surface0;
  box-shadow: none;
}

${P} scrolledwindow,
${P} viewport,
${P} .view,
${P} iconview,
${P} treeview,
${P} textview text,
${P} list,
${P} row {
  background-color: @lucent_base;
  color: @lucent_text;
}

${P} .sidebar,
${P} .sidebar .view,
${P} .sidebar row,
${P} placessidebar,
${P} placessidebar row,
${P} stacksidebar,
${P} stacksidebar row,
${P} .shortcuts-pane,
${P} .shortcuts-pane .view {
  background-color: @lucent_mantle;
  color: @lucent_subtext;
}

${P} .view:selected,
${P} iconview:selected,
${P} treeview:selected,
${P} row:selected,
${P} flowboxchild:selected,
${P} .sidebar .view:selected,
${P} .sidebar row:selected,
${P} placessidebar row:selected,
${P} stacksidebar row:selected,
${P} .shortcuts-pane .view:selected,
${P} entry selection,
${P} textview text selection,
${P} label selection {
  background-color: @lucent_mauve;
  color: @lucent_crust;
}

${P} treeview header button {
  background-color: @lucent_mantle;
  background-image: none;
  color: @lucent_subtext;
  border-color: @lucent_surface0;
  box-shadow: none;
}

${P} separator {
  background-color: @lucent_surface0;
}

/* GtkPaned's handle is several pixels wide, and a status bar beside a sidebar
   leaves its foot showing: filled to match, with a 1px line on its edge. */
${P} paned > separator {
  background-color: @lucent_mantle;
  background-image: linear-gradient(@lucent_surface0, @lucent_surface0);
  background-size: 1px 100%;
  background-repeat: no-repeat;
  background-position: left;
}

${P} frame > border,
${P} .frame {
  border-color: @lucent_surface0;
}

${P} link,
${P} *:link {
  color: @lucent_mauve;
}

${P} label:disabled {
  color: @lucent_overlay;
}

/* ── entries ──────────────────────────────────────────────────────────────── */
${P} entry,
${P} spinbutton:not(.vertical) {
  background-color: @lucent_crust;
  background-image: none;
  color: @lucent_text;
  border-color: @lucent_surface0;
  box-shadow: none;
}

${P} entry:focus,
${P} spinbutton:focus:not(.vertical) {
  border-color: @lucent_mauve;
  box-shadow: inset 0 0 0 1px @lucent_mauve;
}

/* ── buttons ──────────────────────────────────────────────────────────────── */
${P} button {
  background-color: @lucent_surface0;
  background-image: none;
  color: @lucent_text;
  border-color: @lucent_surface0;
  box-shadow: none;
  text-shadow: none;
  -gtk-icon-shadow: none;
}

${P} button:hover {
  background-color: @lucent_surface1;
  border-color: @lucent_surface1;
}

/* Flat buttons — toolbars, header bars, sidebars, path bars — stay flat. */
${P} button.flat,
${P} headerbar button,
${P} toolbar button,
${P} .toolbar button,
${P} .inline-toolbar button,
${P} .sidebar button,
${P} .path-bar button,
${P} .path-bar-button,
${P} notebook > header button {
  background-color: transparent;
  border-color: transparent;
}

${P} button.flat:hover,
${P} headerbar button:hover,
${P} toolbar button:hover,
${P} .toolbar button:hover,
${P} .inline-toolbar button:hover,
${P} .sidebar button:hover,
${P} .path-bar button:hover,
${P} .path-bar-button:hover,
${P} notebook > header button:hover {
  background-color: @lucent_surface0;
}

${P} button:active,
${P} button:checked,
${P} button.suggested-action {
  background-color: @lucent_mauve;
  border-color: @lucent_mauve;
  color: @lucent_crust;
}

${P} button.destructive-action {
  background-color: @lucent_red;
  border-color: @lucent_red;
  color: @lucent_crust;
}

${P} button:disabled {
  background-color: transparent;
  color: @lucent_overlay;
}

/* ── checks, radios, switches, sliders, bars ─────────────────────────────── */
${P} check,
${P} radio {
  background-color: @lucent_crust;
  background-image: none;
  border: 1px solid @lucent_surface1;
  color: @lucent_crust;
  box-shadow: none;
}

${P} check:checked,
${P} check:indeterminate,
${P} radio:checked {
  background-color: @lucent_mauve;
  border-color: @lucent_mauve;
  color: @lucent_crust;
}

${P} switch {
  background-color: @lucent_surface0;
  background-image: none;
  border-color: @lucent_surface0;
  color: @lucent_text;
}

${P} switch:checked {
  background-color: @lucent_mauve;
  border-color: @lucent_mauve;
  color: @lucent_crust;
}

${P} switch slider,
${P} scale slider {
  background-color: @lucent_text;
  background-image: none;
  border-color: @lucent_surface1;
  box-shadow: none;
}

${P} scale trough,
${P} progressbar trough,
${P} levelbar trough {
  background-color: @lucent_surface0;
  background-image: none;
  border-color: @lucent_surface0;
}

${P} scale highlight,
${P} progressbar progress,
${P} levelbar block.filled {
  background-color: @lucent_mauve;
  background-image: none;
  border-color: @lucent_mauve;
}

/* ── tabs and scrollbars ─────────────────────────────────────────────────── */
${P} notebook > header {
  background-color: @lucent_mantle;
  border-color: @lucent_surface0;
}

${P} notebook > header tab {
  color: @lucent_subtext;
}

${P} notebook > header tab:checked {
  color: @lucent_text;
  box-shadow: inset 0 -3px @lucent_mauve;
}

${P} notebook > stack:not(:only-child) {
  background-color: @lucent_base;
}

${P} scrollbar {
  background-color: transparent;
  border-color: transparent;
}

${P} scrollbar slider {
  background-color: @lucent_surface1;
}

${P} scrollbar slider:hover {
  background-color: @lucent_overlay;
}

${P} .rubberband,
${P} rubberband {
  background-color: alpha(@lucent_mauve, 0.25);
  border: 1px solid @lucent_mauve;
}

/* ── menus, popovers, tooltips ────────────────────────────────────────────── */
${P} menu,
${P} .menu,
${P} .context-menu,
popover${P},
tooltip${P} {
  background-color: @lucent_mantle;
  color: @lucent_text;
  border: 1px solid @lucent_surface0;
}

${P} menu menuitem,
${P} .menu menuitem {
  color: @lucent_text;
}

${P} menu menuitem:hover,
${P} .menu menuitem:hover,
${P} menubar > menuitem:hover {
  background-color: @lucent_mauve;
  color: @lucent_crust;
}

${P} menu menuitem:disabled,
${P} .menu menuitem:disabled {
  color: @lucent_overlay;
}

${P} menu separator,
${P} .menu separator {
  background-color: @lucent_surface0;
}

tooltip${P} * {
  color: @lucent_text;
}
CSS
    } | emit "$CFG/gtk-3.0/lucent.css"
    ensure_css_import "$CFG/gtk-3.0/gtk.css"

    {
        echo "/* Generated by theme.sh — edits here are overwritten."
        echo "   Active theme: ${C[name]:-unknown}"
        echo "   Imported by gtk.css; see theme.sh's render_gtk_user_css. */"
        gtk_named_colors
        cat <<CSS

/* libadwaita's colours. Plain GTK 4 apps do not read these. */
:root {
  --window-bg-color: #${C[base]};
  --window-fg-color: #${C[text]};
  --view-bg-color: #${C[base]};
  --view-fg-color: #${C[text]};
  --headerbar-bg-color: #${C[mantle]};
  --headerbar-fg-color: #${C[text]};
  --headerbar-border-color: #${C[surface0]};
  --headerbar-backdrop-color: #${C[mantle]};
  --sidebar-bg-color: #${C[mantle]};
  --sidebar-fg-color: #${C[text]};
  --sidebar-backdrop-color: #${C[mantle]};
  --sidebar-border-color: #${C[surface0]};
  --card-bg-color: #${C[mantle]};
  --card-fg-color: #${C[text]};
  --dialog-bg-color: #${C[mantle]};
  --dialog-fg-color: #${C[text]};
  --popover-bg-color: #${C[mantle]};
  --popover-fg-color: #${C[text]};
  --accent-bg-color: #${C[mauve]};
  --accent-fg-color: #${C[crust]};
  --accent-color: #${C[mauve]};
}
CSS
    } | emit "$CFG/gtk-4.0/lucent.css"
    ensure_css_import "$CFG/gtk-4.0/gtk.css"
}

# The palette as named colours: lucent_* for the rules above (prefixed, since
# named colours are global and an app's own @text or @red must not change
# under it), and GTK's own theme_* names, which some apps' stylesheets use —
# swayosd's, for one.
gtk_named_colors() {
    local role
    for role in crust mantle base surface0 surface1 overlay subtext text red mauve; do
        printf '@define-color lucent_%-8s #%s;\n' "$role" "${C[$role]}"
    done
    printf '@define-color %-24s #%s;\n' \
        theme_bg_color "${C[base]}" theme_fg_color "${C[text]}" \
        theme_base_color "${C[base]}" theme_text_color "${C[text]}" \
        theme_selected_bg_color "${C[mauve]}" theme_selected_fg_color "${C[crust]}" \
        theme_unfocused_bg_color "${C[base]}" theme_unfocused_fg_color "${C[text]}" \
        theme_unfocused_base_color "${C[base]}" theme_unfocused_text_color "${C[text]}" \
        theme_unfocused_selected_bg_color "${C[mauve]}" \
        theme_unfocused_selected_fg_color "${C[crust]}" \
        insensitive_fg_color "${C[overlay]}" borders "${C[surface0]}"
}

# One line at the top of a stylesheet (gtk.css, userChrome.css), added if it is
# not there. @import has to come before any rule, so it goes first; whatever
# else the file holds stays.
ensure_css_import() {
    local conf="$1" line='@import url("lucent.css");' tmp
    if [[ -f $conf ]] && grep -qF "$line" "$conf"; then
        return 0
    fi
    mkdir -p "${conf%/*}"
    tmp="$(mktemp "${conf}.XXXXXX")" || return 0
    # An if, not `[[ -f ]] && cat`: with no gtk.css yet that && is the
    # group's last command, its failure fails the write, and the import was
    # never added on exactly the machines that needed it.
    {
        echo "$line"
        if [[ -f $conf ]]; then cat "$conf"; fi
    } > "$tmp" && chmod 644 "$tmp" && mv "$tmp" "$conf" || rm -f "$tmp"
}

# Firefox's toolbars, tabs, address bar and menus. With its "System theme"
# Firefox takes the toolbar colour from GTK's header bar, but in practice it
# came out stock grey whatever gtk.css said, so the palette goes straight into
# Firefox's own colour variables, through userChrome.css. Firefox renames those
# between versions, so both generations are written: 158's and Fedora 44's 150.
#
# For every profile in profiles.ini — under ~/.config/mozilla/firefox, where
# Firefox keeps new profiles now, and ~/.mozilla/firefox, where older installs
# have them:
#
#   chrome/lucent.css    the variables; rewritten on every switch
#   chrome/userChrome.css  one @import of it, added at the top if missing
#   user.js              toolkit.legacyUserProfileCustomizations.stylesheets,
#                        without which Firefox ignores userChrome.css; added
#                        if missing
#
# Firefox reads userChrome.css only at start: a theme switch reaches it on its
# next start. A profile created after the last switch is themed by the next
# login (autostart.lua runs `theme.sh --firefox`) or the next switch.
render_firefox() {
    local root ini rel path dir
    for root in "$CFG/mozilla/firefox" "$HOME/.mozilla/firefox"; do
        ini="$root/profiles.ini"
        [[ -f $ini ]] || continue
        while IFS=$'\t' read -r rel path; do
            [[ -n $path ]] || continue
            if [[ $rel == 1 ]]; then dir="$root/$path"; else dir="$path"; fi
            [[ -d $dir ]] || continue
            firefox_css | emit "$dir/chrome/lucent.css"
            ensure_css_import "$dir/chrome/userChrome.css"
            ensure_line "$dir/user.js" \
                'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
        done < <(awk -F= '
            /^\[/ { if (p != "") print r "\t" p; p = ""; r = "" }
            /^Path=/ { p = substr($0, 6) }
            /^IsRelative=/ { r = $2 }
            END { if (p != "") print r "\t" p }' "$ini")
    done
}

firefox_css() {
    local base="#${C[base]}" mantle="#${C[mantle]}" crust="#${C[crust]}" \
          s0="#${C[surface0]}" s1="#${C[surface1]}" text="#${C[text]}" \
          sub="#${C[subtext]}" accent="#${C[mauve]}"
    cat <<CSS
/* Generated by theme.sh — edits here are overwritten.
   Active theme: ${C[name]:-unknown}
   Imported by userChrome.css; see theme.sh's render_firefox. */
:root {
  --toolbox-background-color: ${mantle} !important;
  --toolbox-text-color: ${text} !important;
  --toolbox-background-color-inactive: ${mantle} !important;
  --toolbox-text-color-inactive: ${sub} !important;
  --toolbar-background-color: ${base} !important;
  --toolbar-text-color: ${text} !important;
  --tab-background-color: transparent !important;
  --tab-background-color-hover: ${s0} !important;
  --tab-background-color-selected: ${base} !important;
  --tab-text-color: ${sub} !important;
  --tab-text-color-hover: ${text} !important;
  --tab-text-color-selected: ${text} !important;
  --tab-line-selected-color: ${accent} !important;
  --tabpanel-background-color: ${base} !important;
  --toolbar-field-background-color: ${crust} !important;
  --toolbar-field-text-color: ${text} !important;
  --toolbar-field-border-color: ${s0} !important;
  --toolbar-field-background-color-focus: ${crust} !important;
  --toolbar-field-text-color-focus: ${text} !important;
  --toolbar-field-border-color-focus: ${accent} !important;
  --toolbarbutton-background-color-hover: ${s0} !important;
  --toolbarbutton-background-color-active: ${s1} !important;
  --urlbarview-background-color-hover: ${s0} !important;
  --urlbarview-background-color-selected: ${accent} !important;
  --urlbarview-text-color-selected: ${crust} !important;
  --urlbarview-separator-color: ${s0} !important;
  --panel-background-color: ${mantle} !important;
  --panel-text-color: ${text} !important;
  --panel-border-color: ${s0} !important;
  --sidebar-background-color: ${mantle} !important;
  --sidebar-text-color: ${text} !important;
  --chrome-content-separator-color: ${s0} !important;
  --focus-outline-color: ${accent} !important;
  /* The same colours under the names older Firefox reads: Fedora 44 has 150.
     Each version ignores the other's. */
  --toolbox-bgcolor: ${mantle} !important;
  --toolbox-textcolor: ${text} !important;
  --toolbox-bgcolor-inactive: ${mantle} !important;
  --toolbox-textcolor-inactive: ${sub} !important;
  --toolbar-bgcolor: ${base} !important;
  --toolbar-color: ${text} !important;
  --tab-selected-bgcolor: ${base} !important;
  --tab-selected-textcolor: ${text} !important;
  --tab-hover-background-color: ${s0} !important;
  --toolbar-field-color: ${text} !important;
  --toolbar-field-focus-background-color: ${crust} !important;
  --toolbar-field-focus-color: ${text} !important;
  --toolbar-field-focus-border-color: ${accent} !important;
  --toolbarbutton-hover-background: ${s0} !important;
  --toolbarbutton-active-background: ${s1} !important;
  --arrowpanel-background: ${mantle} !important;
  --arrowpanel-color: ${text} !important;
  --arrowpanel-border-color: ${s0} !important;
  --urlbarView-highlight-background: ${accent} !important;
  --urlbarView-highlight-color: ${crust} !important;
  --urlbarView-hover-background: ${s0} !important;
  --urlbarView-separator-color: ${s0} !important;
}
CSS
}

# A line in a file, appended if it is not there.
ensure_line() {
    local file="$1" line="$2"
    [[ -f $file ]] && grep -qxF "$line" "$file" && return 0
    mkdir -p "${file%/*}"
    printf '%s\n' "$line" >> "$file"
}

# `theme.sh --firefox`: the current theme into Firefox's profiles and nothing
# else, for autostart.lua to catch a profile made since the last switch.
firefox_only() {
    local slug
    slug="$(cat "$ACTIVE_FILE" 2>/dev/null)" || return 0
    [[ -f "$THEME_DIR/$slug.theme" ]] || return 0
    load_theme "$THEME_DIR/$slug.theme"
    render_firefox
}

# wofi cannot @import: it hands GTK the stylesheet as a string, so GTK has no idea
# where the file lives and resolves a relative @import against the current
# working directory — which is wherever the launcher happened to be started
# from. The colours are written into style.css between markers instead.
patch_wofi_css() {
    local conf="$CFG/wofi/style.css" tmp
    [[ -w $conf ]] || return 0
    if ! grep -q "$WOFI_MARK_BEGIN" "$conf" || ! grep -q "$WOFI_MARK_END" "$conf"; then
        printf 'theme.sh: %s has no theme markers; wofi keeps its current colours\n' \
            "$conf" >&2
        return 0
    fi
    tmp="$(mktemp "${conf}.XXXXXX")" || return 0
    {
        sed "/$WOFI_MARK_BEGIN/q" "$conf"
        define_colors
        printf '* { font-family: "%s", sans-serif; }\n' "${C[font]:-$DEFAULT_FONT}"
        sed -n "/$WOFI_MARK_END/,\$p" "$conf"
    } > "$tmp" && chmod 644 "$tmp" && mv "$tmp" "$conf" || rm -f "$tmp"
}

# foot 1.26 renamed [colors] to [colors-dark] and [colors-light], and 1.28
# removed the old name; Ubuntu 26.04 has 1.25 and Fedora 43 1.24, which know
# only [colors]. So the section is chosen by the version installed, and the
# new one if foot cannot be asked.
foot_has_color_themes() {
    local v
    v="$(foot --version 2>/dev/null | sed -n 's/^foot version: \([0-9]*\.[0-9]*\).*/\1/p')"
    [[ -z $v ]] && return 0
    (( ${v%%.*} > 1 || ${v#*.} >= 26 ))
}

# A theme's `terminal` names the theme whose palette foot gets. Rendered by
# loading that theme into C for the length of render_foot_palette and putting
# this one back, so the renderer has one palette to read. A missing theme is a
# warning, not a failure: the terminal falls back to this theme's own colours.
render_foot() {
    local other="${C[terminal]:-}" key
    if [[ -z $other ]]; then
        render_foot_palette
        return
    fi
    if [[ ! -f $THEME_DIR/$other.theme ]]; then
        printf 'theme.sh: terminal theme %s not found; using %s\n' \
            "$other" "${C[name]:-this theme}" >&2
        render_foot_palette
        return
    fi
    local -A outer=()
    for key in "${!C[@]}"; do outer[$key]="${C[$key]}"; done
    load_theme "$THEME_DIR/$other.theme"
    # The font and the opacity are the desktop theme's, not the terminal
    # palette's.
    unset 'C[mono]' 'C[terminal_alpha]'
    [[ -n ${outer[mono]:-} ]] && C[mono]="${outer[mono]}"
    [[ -n ${outer[terminal_alpha]:-} ]] && C[terminal_alpha]="${outer[terminal_alpha]}"
    C[name]="${outer[name]:-} (terminal: ${C[name]:-$other})"
    render_foot_palette
    C=()
    for key in "${!outer[@]}"; do C[$key]="${outer[$key]}"; done
}

render_foot_palette() {
    local mode="${C[mode]:-dark}"
    {
        echo "# Generated by theme.sh — edits here are overwritten."
        echo "# Active theme: ${C[name]:-unknown}"
        echo
        # foot.ini's font= comes before its include of this file, so a
        # theme's mono replaces it. The Nerd Font symbols follow as a
        # fallback, for prompts that draw icons.
        if foot_has_color_themes || [[ -n ${C[mono]:-} ]]; then
            echo "[main]"
        fi
        [[ -n ${C[mono]:-} ]] &&
            echo "font=${C[mono]}:size=11.5, Symbols Nerd Font Mono:size=11.5"
        if foot_has_color_themes; then
            # The light section also makes dimmed text blend towards white.
            echo "initial-color-theme=$mode"
            echo
            echo "[colors-$mode]"
        else
            echo
            echo "[colors]"
        fi
        # foot.ini's translucency over a dark wallpaper only greys a light
        # theme out, so a light one is opaque.
        if [[ -n ${C[terminal_alpha]:-} ]]; then
            echo "alpha=${C[terminal_alpha]}"
        elif [[ $mode == light ]]; then
            echo "alpha=1.0"
        else
            echo "alpha=0.95"
        fi
        echo "foreground=${C[text]}"
        echo "background=${C[base]}"
        echo "selection-foreground=${C[base]}"
        echo "selection-background=${C[rosewater]}"
        echo "cursor=${C[base]} ${C[rosewater]}"
        echo "urls=${C[rosewater]}"
        echo
        # Black and white are the two ANSI colours that assume a background.
        # Programs print "black" as text and "white" as a fill, so on a light
        # theme black has to be dark and white light — the swap every light
        # terminal scheme makes.
        if [[ $mode == light ]]; then
            echo "regular0=${C[subtext]}"
            echo "bright0=${C[overlay]}"
            echo "regular7=${C[surface1]}"
            echo "bright7=${C[surface0]}"
        else
            echo "regular0=${C[surface1]}"
            echo "bright0=${C[overlay]}"
            echo "regular7=${C[subtext]}"
            echo "bright7=${C[text]}"
        fi
        local n role=(_ red green yellow blue pink teal)
        for n in 1 2 3 4 5 6; do
            echo "regular$n=${C[${role[n]}]}"
            echo "bright$n=${C[${role[n]}]}"
        done
    } | emit "$CFG/foot/colors.ini"
}

# mako has no variables, so the colours and every section that sets one live
# here. config includes this before declaring any section of its own.
render_mako() {
    {
        echo "# Generated by theme.sh — edits here are overwritten."
        echo "# Active theme: ${C[name]:-unknown}"
        echo
        # After config's own font=, which this include follows, so it wins.
        [[ -n ${C[font]:-} ]] && echo "font=${C[font]} 11"
        echo "background-color=#${C[base]}e6"
        echo "text-color=#${C[text]}"
        echo "border-color=#${C[mauve]}"
        echo "progress-color=over #${C[surface1]}"
        echo
        echo "[urgency=low]"
        echo "border-color=#${C[surface1]}"
        echo "text-color=#${C[subtext]}"
        echo "default-timeout=4000"
        echo
        echo "[urgency=normal]"
        echo "border-color=#${C[mauve]}"
        echo
        echo "[urgency=critical]"
        echo "border-color=#${C[red]}"
        echo "background-color=#${C[base]}f2"
        echo "text-color=#${C[red]}"
        echo "# Critical notifications stay until dismissed."
        echo "default-timeout=0"
    } | emit "$CFG/mako/colors"
}

# hyprlock keeps its palette inline. Replace the value of each `$name = rgb(..)`
# line and the two hex literals inside the pango markup, leaving all else alone.
patch_hyprlock() {
    local conf="$CFG/hypr/hyprlock.conf" tmp
    [[ -w $conf ]] || return 0
    tmp="$(mktemp "${conf}.XXXXXX")"
    awk -v c_text="${C[text]}"       -v c_mauve="${C[mauve]}" \
        -v c_red="${C[red]}"         -v c_surface="${C[surface0]}" \
        -v c_subtext="${C[subtext]}" \
        -v font="${C[font]:-$DEFAULT_FONT}" '
        function setvar(n, v) { return sprintf("$%-7s = rgb(%s)", n, v) }
        /^[[:space:]]*\$text[[:space:]]*=/    { print setvar("text",    c_text);    next }
        /^[[:space:]]*\$mauve[[:space:]]*=/   { print setvar("mauve",   c_mauve);   next }
        /^[[:space:]]*\$red[[:space:]]*=/     { print setvar("red",     c_red);     next }
        /^[[:space:]]*\$surface[[:space:]]*=/ { print setvar("surface", c_surface); next }
        # Pango markup inside hyprlang escapes "#" as "##".
        /placeholder_text/ { sub(/##[0-9a-fA-F]{6}/, "##" c_subtext); print; next }
        /fail_text/        { sub(/##[0-9a-fA-F]{6}/, "##" c_red);     print; next }
        # The family is replaced and a weight after it kept: "<font> ExtraBold".
        /^[[:space:]]*font_family[[:space:]]*=/ {
            match($0, /^[[:space:]]*font_family[[:space:]]*=[[:space:]]*/)
            w = ""
            if ($0 ~ / ExtraBold[[:space:]]*$/) w = " ExtraBold"
            print substr($0, 1, RLENGTH) font w; next
        }
        { print }
    ' "$conf" > "$tmp" && chmod 644 "$tmp" && mv "$tmp" "$conf" || rm -f "$tmp"
}

# foot reads colors.ini once, at start, and has no reload. But a terminal
# takes new colours from escape sequences in its own output, so each open
# window is recoloured by writing them to its pty: OSC 4 for the sixteen
# palette entries, 10 and 11 for foreground and background (foot accepts the
# alpha as a [percent] prefix), 12 for the cursor, 17 and 19 for the
# selection. The sequences are built from the colors.ini just written, so
# there is one palette, not two. The URL colour has no sequence and stays as
# it was until the window is reopened, and a program that resets the palette
# (OSC 104) gets the colours foot started with.
recolor_foot() {
    local ini="$CFG/foot/colors.ini" seq pid child pts
    [[ -r $ini ]] || return 0
    seq="$(awk -F= '
        /^\[/ || /^#/ || NF < 2 { next }
        { k = $1; v = $2; gsub(/[ \t]/, "", k); sub(/^[ \t]+/, "", v) }
        k ~ /^regular[0-7]$/ { printf "\033]4;%d;#%s\033\\", substr(k, 8), v }
        k ~ /^bright[0-7]$/  { printf "\033]4;%d;#%s\033\\", substr(k, 7) + 8, v }
        k == "foreground"    { printf "\033]10;#%s\033\\", v }
        k == "background"    { bg = v }
        k == "alpha"         { alpha = int(v * 100 + 0.5) }
        k == "cursor"        { split(v, c, " "); if (c[2] != "") printf "\033]12;#%s\033\\", c[2] }
        k == "selection-background" { printf "\033]17;#%s\033\\", v }
        k == "selection-foreground" { printf "\033]19;#%s\033\\", v }
        END {
            if (bg != "") {
                if (alpha != "") printf "\033]11;[%d]#%s\033\\", alpha, bg
                else printf "\033]11;#%s\033\\", bg
            }
        }' "$ini")"
    [[ -n $seq ]] || return 0
    # A foot window's pty is the one its child, the shell, has open. Every
    # terminal of a foot --server shows up as a child of the server.
    for pid in $(pgrep -u "$UID" -x foot); do
        for child in $(pgrep -P "$pid"); do
            pts="$(readlink "/proc/$child/fd/0" 2>/dev/null)" || continue
            [[ $pts == /dev/pts/* && -w $pts ]] || continue
            timeout 1 bash -c 'printf "%s" "$1" > "$2"' _ "$seq" "$pts" 2>/dev/null || true
        done
    done
}

# The starch lattice comes in a dark and a light render. When the wallpaper
# is one of them, a theme of the other mode swaps it for its twin at the
# same size: the dark lattice behind a light theme read as a hole in the
# desktop. Any other wallpaper is somebody's choice and is left alone.
match_wallpaper() {
    local active="$CFG/hypr/.active-wallpaper" img name dir want
    local script="$CFG/hypr/scripts/wallpaper.sh"
    [[ -r $active && -x $script ]] || return 0
    img="$(<"$active")"
    dir="${img%/*}"; name="${img##*/}"
    [[ $name =~ ^starch-lattice(-light)?-([0-9]+x[0-9]+)\.png$ ]] || return 0
    if [[ ${C[mode]:-dark} == light ]]; then
        want="$dir/starch-lattice-light-${BASH_REMATCH[2]}.png"
    else
        want="$dir/starch-lattice-${BASH_REMATCH[2]}.png"
    fi
    [[ $want != "$img" && -f $want ]] || return 0
    if [[ $RELOAD -eq 1 ]]; then
        "$script" --set "$want" >/dev/null 2>&1 || true
    else
        "$script" --no-reload --set "$want" >/dev/null 2>&1 || true
    fi
}

reload_apps() {
    [[ $RELOAD -eq 1 ]] || return 0
    hyprctl reload >/dev/null 2>&1 || true
    # The shell watches the palette itself and restarts only for a new icon
    # theme.
    "$CFG/hypr/scripts/bar.sh" --theme 2>/dev/null || true
    makoctl reload >/dev/null 2>&1 || true
    recolor_foot
}

apply() {
    local slug="$1"
    load_theme "$THEME_DIR/$slug.theme"
    render_hypr
    render_gtk_css "$CFG/lucent/colors.css"
    render_font_css
    patch_wofi_css
    render_foot
    render_mako
    patch_hyprlock
    # Before set_gtk_mode: GTK 3 rereads gtk.css when the theme name changes,
    # so the rules have to be in place when it does.
    render_gtk_user_css
    render_firefox
    set_gtk_mode
    match_wallpaper
    printf '%s\n' "$slug" > "$ACTIVE_FILE"
    reload_apps
    [[ $RELOAD -eq 1 ]] && note "Theme" "${C[name]:-$slug}"
    return 0
}

list_themes() {
    local f slug name
    [[ -d $THEME_DIR ]] || die "no theme directory: $THEME_DIR"
    shopt -s nullglob
    for f in "$THEME_DIR"/*.theme; do
        slug="${f##*/}"; slug="${slug%.theme}"
        name="$(sed -n 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*//p' "$f" | head -1)"
        printf '%s\t%s\n' "$slug" "${name:-$slug}"
    done
    shopt -u nullglob
}

# --no-reload can precede any other argument.
if [[ ${1:-} == --no-reload ]]; then RELOAD=0; shift; fi

case "${1:-}" in
    --list)    list_themes ;;
    --current) cat "$ACTIVE_FILE" 2>/dev/null || echo "unknown" ;;
    --firefox) firefox_only ;;
    --set)
        [[ -n ${2:-} ]] || die "--set needs a theme slug (try --list)"
        apply "$2"
        ;;
    "")
        mapfile -t rows < <(list_themes)
        [[ ${#rows[@]} -gt 0 ]] || die "no themes in $THEME_DIR"
        current="$(cat "$ACTIVE_FILE" 2>/dev/null || true)"
        # Display names go to wofi; the slug is recovered by position, so a
        # name containing anything at all is safe.
        choice="$(printf '%s\n' "${rows[@]#*$'\t'}" \
            | wofi --dmenu --prompt "Theme${current:+ (${current})}" \
                   --width 420 --height 400 --cache-file /dev/null --insensitive)" || exit 0
        [[ -n $choice ]] || exit 0
        for row in "${rows[@]}"; do
            if [[ ${row#*$'\t'} == "$choice" ]]; then apply "${row%%$'\t'*}"; exit 0; fi
        done
        die "no theme named $choice"
        ;;
    *) die "unknown option: $1 (try --list)" ;;
esac
