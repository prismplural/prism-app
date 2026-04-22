# Prism — Linux packaging assets

Shared metadata used by Flatpak, `.deb`, and AUR packaging. Kept outside
`app/linux/` so Flutter's scaffold regeneration never clobbers them.

## Contents

- `com.prismplural.prism.desktop` — Desktop entry (menus, dock)
- `com.prismplural.prism.metainfo.xml` — AppStream metadata (GNOME Software, KDE Discover, Flathub)
- `icons/hicolor/<size>x<size>/apps/com.prismplural.prism.png` — Icons at 16, 32, 48, 64, 128, 256, 512, 1024 px

All files use the reverse-DNS app ID `com.prismplural.prism`, matching the
iOS / macOS bundle identifier.

## Install layout

For system packages (`.deb`, AUR), install into the standard Freedesktop
hierarchy under `/usr`:

```
/usr/bin/prism                                                         # wrapper script (below)
/usr/lib/prism/                                                        # Flutter bundle contents
/usr/share/applications/com.prismplural.prism.desktop
/usr/share/metainfo/com.prismplural.prism.metainfo.xml
/usr/share/icons/hicolor/<size>x<size>/apps/com.prismplural.prism.png
```

For Flatpak, replace `/usr` with `/app` and add the manifest-level socket
permissions.

## Wrapper script

Both `.deb` and AUR packages ship a launcher at `/usr/bin/prism` that forces
XWayland (Flutter has no native Wayland path today — see `build.sh`):

```sh
#!/bin/sh
export GDK_BACKEND=x11
exec /usr/lib/prism/prism_plurality "$@"
```

Flatpak handles this in the manifest via `--env=GDK_BACKEND=x11` plus
`--socket=fallback-x11`.

## Validation

On a Linux host with the Freedesktop tools installed:

```sh
desktop-file-validate com.prismplural.prism.desktop
appstreamcli validate com.prismplural.prism.metainfo.xml
```

## TODO before first Flathub submission

- Host real Linux screenshots at the URLs referenced in `metainfo.xml`
  (currently point at `prismplural.com/assets/screenshots/linux/` which
  doesn't exist yet).
- Add a `<release>` entry for every shipped version going forward.
- Consider providing a scalable SVG icon alongside the PNGs.
