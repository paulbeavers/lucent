-- Programs used by keybinds and rules. Required by the modules that need them,
-- so there is one place to change your terminal or browser.
return {
    terminal     = "~/.config/hypr/scripts/terminal.sh",
    file_manager = "thunar",
    menu         = "wofi --show drun",
    browser      = "firefox",
    editor       = "~/.config/hypr/scripts/terminal.sh -e nvim",
}
