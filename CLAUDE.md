# Working on lucent

The desktop half of [starch](https://github.com/paulbeavers/starch): a script
that turns a fresh Arch install into a Hyprland desktop, the configuration it
deploys, and `lucent-config`. `README.md` is written for someone using it; this
file is for someone changing it.

## The configuration is Lua, and that has consequences

Hyprland 0.55 deprecated the hyprlang `.conf` format and 0.57 removes it.
`config/hypr/*.lua` is the current form. The files still ending in `.conf` —
`hyprlock`, `hypridle`, `hyprpaper` — belong to other programs and keep their
own formats.

**`hyprctl dispatch` now takes Lua, and the old syntax fails silently.** With a
Lua config Hyprland wraps everything after `dispatch` in `return
hl.dispatch(...)` and evaluates it, so `hyprctl dispatch dpms off` is a syntax
error. The legacy translator is still in the binary but nothing on the IPC path
can reach it, and the error goes back to the caller, which throws it away. This
had quietly broken screen blanking, log out, `SUPER+C/V` and the workspace row
in the bar. Every call in this repo uses the Lua form:

    hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })'

`hyprctl repl` lists what is under `hl.dsp`. Watch for arguments that are
accepted but wrong: `hl.dsp.dpms("off")` is not an error, it silently means
*toggle*. The table form `{ action = "off" }` is what you want.

**Third-party tools that send the old strings cannot be fixed from here.**
Waybar's `hyprland/workspaces` hardcodes `dispatch workspace N` with no setting
to change it, which is why the bar draws its workspace row from ten `custom/`
modules instead. Anything new that "does nothing when clicked" is worth
checking here first.

**`hl.config` sets one key and leaves its siblings alone.** That is what makes
`settings.lua` safe: `hyprland.lua` loads it last, so `lucent-config` can
override four input settings without rewriting `input.lua`.

**`settings.lua` is loaded last, which makes it useless for anything the
hand-written modules *act on* rather than read.** Binds are the case in point:
`keybinds.lua` registers all 132 of them when `hyprland.lua` requires it, long
before `settings.lua` exists. That is why the modifier lives in its own
`keys.lua`, which `keybinds.lua` requires itself. Anything else that has to be
decided before a module runs needs the same treatment.

**The modifier is a *trio*: `mod`, `alt` and `solo`.** `keybinds.lua` spells
no modifier literally. Default is `mod=SUPER, alt=ALT, solo=ALT`; picking
Alt/Option in lucent-config gives `mod=ALT, alt=CTRL, solo="ALT + CTRL"`.

Two wrong answers, both of which were written before this one. Reassigning
only `mod` collapses `mod + ALT + H` into `ALT + H` — already Focus left —
eleven collisions Hyprland reports not one of. Then *swapping* the pair, so
the secondary becomes SUPER, fixes every collision and is still wrong: SUPER
is Command, and the whole reason the setting exists is a Mac host that keeps
Command for itself. Thirteen binds would read as bound and never fire, which
beats a collision for being completely silent. **The test for this layout is
that no bind references SUPER at all**, not merely that nothing collides:

    luajit tools/keymap-dump.lua config/hypr ALT | grep SUPER   # must be empty

`solo` exists because `CTRL + Tab` and `CTRL + bracketleft` belong to the
applications running under the compositor, so the three binds that use the
secondary alone take the primary too when ALT leads.

`ALT + CTRL` is a busier namespace than `SUPER + ALT`, because `mod + CTRL`
already carries the resize and silent-workspace binds. That is why the
consume/expel and fit-into-view scrolling binds sit on X and F: on C and V
they collide with Centre window and Toggle floating. Changed in both layouts,
not just the one that needs it, so the keymap keeps one shape. Check both
after touching binds — it normalises modifiers into a modmask the way Hyprland
does, so it catches collisions spelled in a different order that a string
comparison misses:

    luajit tools/keymap-dump.lua config/hypr SUPER   # exits 1 on a collision
    luajit tools/keymap-dump.lua config/hypr ALT

**`hyprctl reload` builds a fresh Lua state.** Verified on 0.56.2: a global set
through `hyprctl repl` is gone afterwards, and every module is re-`require`d
from disk. So rewriting a generated module and reloading is enough — if the
state had been reused, `require`'s cache would have made a changed `keys.lua`
do nothing until the next login, silently.

**`keys.lua` must never be added to `config/`.** It is generated, like
`monitors.lua` and `settings.lua`, and none of those are in the repo. Put it
there and `install.sh` deploys it on every run, overwriting the chosen
modifier — and because the sync only backs up files that differ, it would look
like the setting simply refused to stick.

Check a change with `Hyprland --verify-config -c config/hypr/hyprland.lua`,
which needs no running compositor, or `hyprctl configerrors` in a session.

## install.sh

**Three distros, one desktop.** `DISTRO` (arch | fedora | ubuntu, from
`/etc/os-release`) selects the package lists, the package manager, the greeter
account and where Hyprland comes from. Everything under `config/` is shared and
must stay distro-neutral. A package added to one list needs its counterpart in
the other two; names differ often — Fedora has `python3-gobject`, `Thunar`,
`qt6-qtwayland`, Ubuntu has `python3-gi`, `mako-notifier`, `libnotify-bin`,
`fd-find`, `qtwayland5`. `dnf repoquery <name>` answers on a Fedora box; for
Ubuntu, nothing local does, so check the archive before writing a name down:

    curl -s "https://people.canonical.com/~ubuntu-archive/madison.cgi?package=NAME&s=resolute&a=&c=&t="

Only one suite per query — a comma-separated list silently returns nothing.
The PPA's own contents come from the Launchpad API (`getPublishedSources` /
`getPublishedBinaries`, which paginate; `total_size` tells you if you only got
the first page). A source published for a series does not mean a binary was
built for it: `uwsm` is a published source for resolute with no binary, and
PPA `waybar` is amd64-only.

Neither Fedora nor Ubuntu has a Hyprland of its own. In both cases an installed
build or an already-enabled repository is always respected, and the default —
`nett00n/hyprland` COPR, `ppa:cppiber/hyprland` — is enabled only when nothing
provides it.

**Ubuntu's floor is 26.04, and both reasons matter.** The PPA reaches only
0.54.3 on 24.04, below the 0.55 that reads the Lua config; and 24.04's archive
has no `swayosd`, which is the *only* thing bound to the volume, mute and
brightness keys — so a 24.04 desktop would come up with those keys silently
dead, which is this repo's least favourite failure mode. An older release is
refused by codename, not version number: a derivative reports its own
`VERSION_ID` (Mint 23 is Ubuntu 26.04), so `UBUNTU_CODENAME` is the only field
that says which archive is underneath. Every codename *below* the floor is
listed, so an unrecognised one can only be newer and proceeds with a warning
rather than refusing a release that did not exist yet.

**The login manager is SDDM on Arch and greetd + tuigreet elsewhere.** Arch
switched on 2026-10-26: tuigreet draws on the text console, and its box came
out as stray characters, inconsistently and worst on slow machines. SDDM is
set up as Omarchy sets it up — its Qt 6 greeter drawn by Hyprland, under a
theme of our own (`sddm/lucent/`, laid out like `hyprlock.conf`). Three things
about it are not visible from the code:

- **The greeter's Hyprland gets a config of its own, `/etc/lucent/greeter.lua`,**
  built by `write_greeter` from the desktop's generated `monitors.lua`,
  `gpu.lua` and `keyboard.lua`. The greeter runs as `sddm` and cannot read a
  home directory, so they are copied, and the config phase rebuilds the copy
  every run. Without them the login screen would have the wrong scale, the
  wrong keyboard layout and, under UTM or Parallels, two pointers.
- **`metadata.desktop` must say `QtVersion=6`.** Without it SDDM starts its
  Qt 5 greeter, which needs `qt5-declarative`, which nothing installs: no
  login screen at all.
- **An Arch machine with our greetd is migrated, not deferred to.** greetd
  holding the alias would otherwise read as someone else's display manager.
  The `Managed by` marker in `/etc/greetd/config.toml` identifies it; a re-run
  disables greetd, removes `greetd` and `greetd-tuigreet`, and enables SDDM.

Test the theme without logging out, against the installed copy:
`sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/lucent`.

**The greetd account is named differently on Fedora and Ubuntu**, and
`config.toml` naming one that does not exist is a login screen that never
appears: `greetd` on Fedora, `_greetd` on Debian and Ubuntu (from the
package's `sysusers.d`). Ubuntu also arbitrates through
`/etc/X11/default-display-manager` as well as the systemd alias — a display
manager installed later reads that file to decide whether to take the alias
back, so the unit alone does not keep greetd in charge.

**`grep -s` still exits 2 on a missing file**, and under `set -o pipefail` that
exit comes out of the whole pipeline and reads as "no match". 26.04 is
deb822-only and ships no `/etc/apt/sources.list` at all, so the universe check
failed on every real machine: each run decided universe needed adding, the
system phase could never report itself complete, and a re-run never became the
config-only refresh it is supposed to be. `apt_component_enabled` now passes
grep only the paths that exist.

**Ubuntu's installed-package set is cached**, because `pkg_installed` is called
once per name in `WANTED` and one `dpkg-query` pass costs the same as one
lookup. It is read before anything is installed, so `UBUNTU_PKGSET=""` after
`apt-get install` is not optional — without it every package just installed
reads back as still missing and the run reports all of them as skipped.

**apt has no `--skip-unavailable`.** One unknown name fails the whole
transaction, so anything no enabled repository offers is filtered out *before*
`apt-get` sees it. That filter has to wait for both universe and the Hyprland
PPA, or the first run writes the entire desktop off as unavailable and then
leaves it uninstalled on the very run that enables the component.

**Ubuntu's `firefox` is a transitional stub** that installs snapd and the
snap, and it carries a *higher* version than Mozilla's real `.deb`, so the
pin in `/etc/apt/preferences.d/mozilla` is what makes the repository work at
all. Without it apt keeps choosing the snap.

**It does not touch the boot.** No Plymouth, initramfs or kernel command line:
the splash lives in starch, which owns the machines it installs. It used to live
here, and on Fedora that meant a desktop install replacing the distro's boot
theme and rebuilding every initramfs.

**starch reads the package lists out of this file.** Its `extract-packages.sh`
takes `^PKGS_...=(` through `^)` with sed, so the Arch arrays must stay at
column 0, and anything between them — the sed range runs past one-line arrays
to the next column-0 `)` — is evaluated there with `set -u` and no `DISTRO`.
That is why both the Fedora and the Ubuntu override blocks are indented and
test `${DISTRO:-}` rather than `$DISTRO`: they are inside the swallowed range
and get evaluated by starch too. After touching any of them, check the ISO list
did not move:

    diff <(cd ../starch && ./extract-packages.sh) <previous output>

Idempotent by design: a second run detects that packages and services are in
place and becomes a config sync. It backs up only files that actually changed.
`monitors.lua` is left alone once written, so a hand-tuned layout survives,
and so is the lid drop-in — lucent-config owns it afterwards. It used to be
rewritten whenever it differed from the default, which put a lid set to
"lock" in lucent-config back to suspend on the next run, silently.

**The repo was `hyprland-setup` until 2026-10-17**, and installed machines
still say so: `/etc/greetd/config.toml` carries `Managed by hyprland-setup`,
and that marker is how a re-run knows greetd is already done. The check
accepts both names. Drop the old one and every existing install treats its
own greetd config as foreign, and the system phase stops reporting complete.

The settings app was `starch-config` until the same day, and the rename left
three things for an installed machine that the code still has to handle:

- install.sh removes `/usr/local/lib/starch-config`, its `/usr/local/bin`
  link and its `.desktop` file, or the launcher shows two "Settings".
- `~/.config/starch/settings.json` became `~/.config/lucent/settings.json`,
  and `10-starch-lid.conf` became `10-lucent-lid.conf`. Each old name is
  read while the new file is absent and removed when the new one is written;
  install.sh renames an old lid file in place. Drop the fallbacks and an
  install that had turned the welcome page off gets it back, and one with its
  lid set to "lock" goes back to suspending.
- Generated files written before the rename still say `Generated by
  starch-config` in their header. Harmless; they change on the next save.

**Grep for the halves, not just the name.** The title bar spelled it as two
labels, `"starch"` and `"config"`, and survived a rename that searched for
`starch-config`. The lid path lived in install.sh *and* lucent-config, and
renaming one left the other recreating the old file on every run. Before
calling a rename done, `grep -rni starch` and account for every hit.

**Anything `*.sh` under `config/` is chmod 755 on deploy**, deliberately:
install media strips modes, so without it every keybind that runs a script is a
silent no-op. A new script that is not `*.sh` will not get the bit.

## lucent-config

GTK4 through PyGObject, **deliberately without libadwaita** — it encodes
GNOME's design language and resists being overridden.

- **`sidebar`, `titlebar` and `card` are built-in GTK style classes** with
  their own backgrounds and `:backdrop` variants. Styling them is arguing with
  Adwaita, and Adwaita's more specific selectors win. Every class here is
  namespaced `sc-`. Suspect this first for "my CSS is being ignored".
- **Translucency is not symmetric.** A dark `@base` at 60% over a wallpaper
  still reads dark; a light one turns grey and swallows its own dark text.
  `theme.py` decides light-vs-dark from `@base` luminance and the stylesheet
  carries two sets of alphas. Test any visual change against Catppuccin Latte.
- It is themed from `waybar/colors.css`, the palette `theme.sh` already
  renders, watched via a monitor on the *directory* — `theme.sh` moves a temp
  file into place, so a watch on the old inode goes deaf after one switch.
- It never edits a hand-written config. It owns `monitors.lua`,
  `hypridle.conf` and `settings.lua`, rewrites them whole and keeps a `.bak`.
  Outside the home directory it owns one file,
  `/etc/systemd/logind.conf.d/10-lucent-lid.conf`, written through pkexec.
- Its own record of choices, `~/.config/lucent/settings.json`, holds only
  what cannot be read back from the system — today just "show at login". It
  is created the first time that switch is touched, so its absence is normal.

Display scale is the setting worth understanding: a scale is legal only if it
is a multiple of 1/120 *and* divides the resolution into whole pixels both
ways. Hyprland accepts anything and then silently snaps, so a config can say
1.5 while the session runs at 1.6. `scales.py` enumerates the legal ones.

## The terminal is foot, not kitty

kitty draws with OpenGL. Under UTM on a Mac it opened an empty window, which
is worse than failing: `terminal.sh` used to fall back to foot when kitty
*exited* at launch, and an empty window never exits. foot draws on the CPU, so
it opens on any graphics stack, and since 2026-10-25 it is the only terminal.
What that gave up: ligatures, kitty's image protocol (foot does sixel), and
live theme changes — foot reads `colors.ini` at start, so a theme switch
reaches new terminals only.

**foot's colour section depends on its version.** 1.26 renamed `[colors]` to
`[colors-dark]` and `[colors-light]`, and 1.28 removed the old name; Ubuntu
26.04 ships 1.25 and Fedora 43 1.24. `theme.sh` asks `foot --version`. Check a
rendered config with `foot --check-config -c FILE`, which exits non-zero on
any unknown key or section.

## Traps that cost a day each

**The wallpaper is swaybg now, and that was the fix.** hyprpaper's apply is an
IPC call that answers "ok" whether or not it has a surface to paint on, and
0.8.4 has no verb to ask what it is showing — so a bare desktop could not be
told from a working one, and three rounds of timeout tuning chased a race that
may never have been the problem. On install media it never answered at all:
`/tmp/wallpaper.log` read "did not answer in 10s" and then "would not accept",
after twenty seconds of waiting, on every boot.

swaybg takes the image as an argument. No daemon, no socket, no ordering —
`autostart.lua` calls `wallpaper.sh --restore` and nothing has to be waited
for. Changing wallpaper replaces the process: start the new one, then kill the
old, so the bare compositor never shows between them.

Two things from that episode are worth keeping. `wallpaper.sh` still writes a
line to `/tmp/wallpaper.log`, because a wallpaper that does not appear leaves no
other trace on the machine it happened on. And a VM cannot test any of this:
`-vga std` gives no usable GL, so hyprpaper could not paint there by any route,
and I read its "no target" message as a config mismatch when it meant "no
surface" — then built a fix on that reading. Wallpaper behaviour is judged on
real hardware or not at all.

## Broadcom: check the kernel's table, not a datasheet

`WL_IDS` in `install.sh` and `installer/broadcom-live` is the list of cards the
in-kernel drivers *cannot* drive. Two were wrong — 43ba (BCM43602) and 43a3
(BCM4350) — and brcmfmac claims both outright and ships their firmware, so
listing them blacklisted the driver that works and loaded `wl`, which cannot
bind them. A 2013 15" MacBook Pro had no wireless at all as a result. Before
adding an id:

    modinfo brcmfmac | grep -oiE 'd0000[0-9A-F]{4}'

If brcmfmac claims it, `wl` is the wrong answer. And `wl` matches on PCI
*class*, not device id, so it is autoloaded for cards it cannot drive and
races the right driver — which is why a card that is not on the list now gets
`blacklist wl` written for it rather than nothing.

## Parallels on a Mac: the display and the cursor

Fedora aarch64 under Parallels, virtio-gpu (vendor 0x1af4, so `gpu_has
virtual`), `systemd-detect-virt` says `parallels`. GNOME looks right there out
of the box; Hyprland did not, in four ways.

**Black bars left and right, cursor still visible in them.** `monitors.lua`
said `highrr`, and a virtual display advertises thirty-odd modes all near
60Hz, so that picked 1600x1200 for a 2936x1846 window and the host
pillarboxed the 4:3 frame. The Mac draws the cursor, which is why it could go
into the bars. On a virtual GPU `install.sh` now writes `preferred` — the
mode that matches the host window, and the one it already worked the scale
out from. Real hardware still gets `highrr`.

**Two cursors, and a pointer that never changed shape.** virtio-gpu only
exposes a cursor plane to an *atomic* client that sets the hotspot client cap.
mutter does; aquamarine never does — not 0.15.1, not master as of 2026-10-17,
and its atomic path never writes the hotspot properties either, so an upgrade
will not help. Under atomic, Hyprland can only draw a software cursor, and
Parallels draws the Mac's over it. The first answer was `cursor.invisible`,
which left the Mac's pointer: one cursor, but never a resize arrow.

What works is `AQ_NO_ATOMIC=1`, aquamarine's legacy DRM path, plus
`no_hardware_cursors = 1`. On that path the Mac's pointer stays hidden behind
Hyprland's software cursor, which changes shape properly. That was found by
testing, not derived; the legacy path sets cursors through
`DRM_IOCTL_MODE_CURSOR2`, which carries a hotspot, and is the likely reason.
`gpu.lua` sets both when `systemd-detect-virt` says `parallels`, `qemu` or
`apple`. The last two are UTM on a Mac (QEMU under Hypervisor.framework, and
Apple's Virtualization framework), added on 2026-10-26 by analogy and not yet
confirmed there. QEMU on a Linux host says `kvm` and hides its own pointer: a
virtio-vga-gl VM with a USB tablet showed one pointer without the fix. On
2026-10-26 the user confirmed one pointer in UTM (`qemu`). UTM also cut rounded
window corners off and left them black; of shadow, blur, `rounding_power` and
`rounding`, only `rounding = 0` fixed it, so `gpu.lua` sets that for `qemu`
and `apple`, and loads after `theme.lua` so it wins. `hl.env` in the config is early enough for `AQ_` variables: the log
shows the config read well before aquamarine opens the GPU. But it only takes
effect **at login**, never on reload.

The hardware plane does show up on the legacy path (planes of type 2 in the
log), and it is the wrong answer. Rendered on the GPU its buffer came out
blank, so the pointer vanished whenever it fitted in the 64x64 plane; with
`use_cpu_buffer = 1` it flickered and hid itself.

**Judge any of this from a fresh login, not from `hyprctl eval`.** Switching
to the software cursor at runtime left the old hardware image on the plane,
which hid the Mac's pointer and made it look as if the software cursor alone
did that. The next config reload cleared the plane and the second pointer came
back. The same thing happened in reverse when a rollback was copied over
`gpu.lua` just before a login: the test that was meant to run never did. Check
`AQ_NO_ATOMIC enabled, using the legacy drm iface` in `hyprland.log` before
believing a result.

**Cursor size is the default 24.** Hyprland's cursor is scaled by the monitor
scale like everything else, so 24 at 1.6 is about the Mac's size. `gpu.lua`
used to set 48, for the Mac's pointer, which showed the guest's image
unscaled; with Hyprland's own cursor that came out double. One fix from that
time still matters: **a reload puts the cursor back to the size Hyprland
launched with**, so `setcursor` reads `$XCURSOR_SIZE` and runs at the top
level of `autostart.lua` as well as in the start handler.

**Option+I "stopped working" after picking 200%.** The window was floating at
x=1843 on a desktop now 1468 wide; lucent-config is single-instance, so the
bind re-presented a window nobody could see. lucent-config now centres its own
window, by pid, after any display change. Option+Ctrl+C does it by hand.

Still open, as of 2026-10-18:

- **Two pointers again along the top edge, on a notched MacBook in full
  screen.** The strip level with the notch is the Mac's menu-bar area: the
  moment the pointer enters it anywhere, the Mac draws its own pointer over
  Hyprland's, and it stays until the pointer goes up to the menu bar and back.
  The workspace numbers sit in that strip, so clicking them is the usual way
  to set it off — which made it look like the fix above coming and going.
  Nothing in the guest changes it. "Optimize for games" does not help, and
  Finder's "Scale to fit below built-in camera" is not offered for Parallels.
  What works is a 16:10 resolution on the Mac (1512x945 rather than 1512x982
  on a 14"), which keeps the whole desktop below the notch — for every Mac
  app too, which is why it is not a default.
- **GNOME left `gsettings` cursor-size at 48.** Everything lucent sets says
  24 and nothing has shown a big cursor since, but if a GTK app ever does,
  that is the first place to look — the settings portal can hand it to GTK.
- **Only 100% and 200% are offered at 2936x1846.** Not a bug: 1846 = 2·13·71,
  so no fraction of 1/120 between 1 and 2 divides both axes. A fixed
  resolution in Parallels (2880x1800 or 2560x1600) gives many more. GNOME
  offered the same two for the same reason. 2560x1600 at 1.6, picked in
  lucent-config, looks sharp on the machine this was worked out on.
- **`prlcc` does not run under Hyprland** — it is Parallels Tools' X11 session
  helper — so clipboard sharing with the Mac probably does not work. Untested.
- lucent-config writes an explicit mode such as `2936x1846@59.98`, which
  stops following the host window if it is resized, and once wrote
  `1600x1200@60.32`, a rate that mode does not have. Not looked into.

## Install the hooks on a fresh clone

`.git/hooks` is not tracked, so a clone has none — and starch's CLAUDE.md says
the submodule pin is automated. On a clone that has not run this, that
statement is false, which is worse than no automation: the next session will
trust it and ship an ISO missing the fix it was built for, which is what
happened twice before the hook existed.

    ./tools/git-hooks/install

`tools/git-hooks/post-commit` is the tracked copy. It finds starch as a sibling
of this repo; set `STARCH_REPO` if they are not side by side. It acts only when
both repos are on `main`.

## Do not run sudo from a tool call

There is no TTY, so sudo cannot prompt, and PAM counts each failure. With
`deny=3` three calls in one chain lock the user out of sudo for ten minutes.
Hand them the command — `./install.sh --configs-only` makes nine sudo calls.
