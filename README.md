# Dotfiles for hosts using finix

This repository is to host configuration files for my systems running [finix](https://github.com/finix-community/finix).

This is a flakeless setup, using [tack](https://https://github.com/manic-systems/tack) for nix pins. Handy for consuming projects that only expose `flake.nix` file. Can be swapped for other options, such as `npins` if one wishes.

Hosts are generated through the top-level `fi.nix` file. Current host entries are:
* `necoarc`: a `x86_64-linux` Lenovo Legion laptop.
  * Runs [Niri](https://github.com/niri-wm/niri) window manager with [ashell](github.com/MalpenZibo/ashell) as status bar. 
* `necomac`: an `aarch64-linux` MacBook M1 Pro with Asahi kernel.
  * Runs [mango](https://github.com/mangowm/mango) window manager with [Waybar](https://github.com/Alexays/Waybar) as status bar.

Both are daily-drive machines and work just fine, though there is always work to be done. Configuration files can be found in their respective directories under *hosts*. Those are largely one big file with stuff like packages from *wrappers* sprinkled in.
