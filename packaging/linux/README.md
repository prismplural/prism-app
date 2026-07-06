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

For Flatpak, the package script installs the same files under `/app`:

```
/app/bin/prism
/app/lib/prism/
/app/share/applications/com.prismplural.prism.desktop
/app/share/metainfo/com.prismplural.prism.metainfo.xml
/app/share/icons/hicolor/<size>x<size>/apps/com.prismplural.prism.png # up to 512 px
```

## Wrapper script

System packages (`.deb`, AUR) ship a launcher at `/usr/bin/prism` that forces
XWayland and exposes bundled audio codecs to `flutter_soloud`:

```sh
#!/bin/sh
export GDK_BACKEND=x11
export LD_LIBRARY_PATH="/usr/lib/prism/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec /usr/lib/prism/prism_plurality "$@"
```

Flatpak uses the same behavior through `/app/bin/prism` plus finish args.

## Flatpak

`scripts/package_linux_flatpak.sh` consumes an existing Flutter Linux release
bundle, creates:

- `Prism-<version>-<arch>.flatpak` — direct install bundle
- `Prism-<version>-<arch>-flatpak-repo.tar.gz` — website-hostable OSTree repo
- `prism.flatpakrepo` and `com.prismplural.prism.flatpakref` — install helpers

The CI job builds the `linux-x64` artifacts after `flutter build linux --release --no-tree-shake-icons`.
Set `FLATPAK_ARCH=aarch64` to produce `linux-arm64` artifact names from an ARM
bundle.

Runtime defaults:

```
org.freedesktop.Platform//25.08
org.freedesktop.Sdk//25.08
```

Finish args:

```
--share=ipc
--share=network
--socket=x11
--socket=pulseaudio
--device=all
--talk-name=org.freedesktop.secrets
--talk-name=org.freedesktop.Notifications
--env=GDK_BACKEND=x11
--env=LD_LIBRARY_PATH=/app/lib/prism/lib
```

`--device=all` is intentional for the first public Flatpak. The current desktop
QR scanner opens `/dev/videoN` directly through V4L2; using the camera portal
would require app/plugin changes. Drop this permission once Prism has a
portal-backed Linux camera path or a separate Flatpak scanner fallback.

Set these environment variables for a signed website repo:

```
FLATPAK_GPG_KEY_ID=<key id>
FLATPAK_GPG_HOMEDIR=<gnupg home>
FLATPAK_GPG_KEY_FILE=<exported public key>
FLATPAK_REPO_URL=https://prismplural.com/flatpak/repo/
FLATPAK_REQUIRE_GPG=1
```

The script exports AppStream metadata into the repository, generates static
deltas, and writes repository summary metadata for Prism's website-hosted
remote.
CI installs Ubuntu's `appstream` and `appstream-compose` packages for this
manual compose step.

Without a GPG key, the script still creates unsigned artifacts for local testing.
Do not publish the repo/ref flow unsigned; users would need to add the remote
with `--no-gpg-verify`.

GitHub Actions imports the signing key from `FLATPAK_GPG_PRIVATE_KEY` and
`FLATPAK_GPG_KEY_ID` secrets. Tag builds and release-attached workflow runs set
`FLATPAK_REQUIRE_GPG=1`, so public release artifacts fail closed until those
secrets are configured.

## Validation

On a Linux host with the Freedesktop tools installed:

```sh
desktop-file-validate com.prismplural.prism.desktop
appstreamcli validate com.prismplural.prism.metainfo.xml
```

## TODO before first public Flatpak listing

- Host real Linux screenshots at the URLs referenced in `metainfo.xml`
  (currently point at `prismplural.com/assets/screenshots/linux/` which
  doesn't exist yet).
- Add a `<release>` entry for every shipped version going forward.
- Consider providing a scalable SVG icon alongside the PNGs.
