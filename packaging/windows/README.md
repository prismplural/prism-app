# Prism Windows installer

Prism's Windows release installer is built with Inno Setup from the Flutter
Windows release bundle.

The installer is intentionally per-user:

```text
%LOCALAPPDATA%\Programs\Prism
```

This avoids a UAC prompt for normal installs and updates. Prism's user data,
secure-storage file, and databases live outside the install directory in the
Windows application support directory derived from the executable metadata
(`CompanyName = Prism Plural`, `ProductName = Prism`). Over-the-top installer
updates replace only the app bundle under `Programs\Prism`; they do not delete
the user's Prism data or crypto material.

## Local build

From a Windows machine with Flutter, Rust, and Inno Setup installed:

```powershell
flutter pub get
flutter build windows --release
powershell -ExecutionPolicy Bypass -File scripts\package_windows_installer.ps1
```

Artifacts are written to `dist/`:

- `Prism-<version>-windows-x64-portable.zip`
- `Prism-<version>-windows-x64-portable.zip.sha256`
- `Prism-<version>-windows-x64-install.exe`
- `Prism-<version>-windows-x64-install.exe.sha256`

The installer bundles Microsoft's latest supported Visual C++ v14 x64
Redistributable from `https://aka.ms/vc14/vc_redist.x64.exe`. During install,
Prism checks the registered runtime version and runs the redistributable only
when the x64 runtime is missing or older than the bundled copy. To build with a
pre-downloaded redistributable instead, set `PRISM_VC_REDIST_X64_PATH` or pass
`-VCRedistPath path\to\vc_redist.x64.exe`.

Because the redistributable installs shared system runtime files, Windows may
show an administrator approval prompt only on machines where the runtime is
missing or outdated.

The portable zip does not run system prerequisites; portable users may still
need to install the same redistributable manually.

## Code signing

Unsigned installers are useful for CI smoke tests, but public release builds
should be Authenticode signed. The first signing target should be the installer
itself; the stronger setup is to sign the bundled `.exe` and `.dll` files
before compiling the installer, then let Inno Setup sign the installer and
generated uninstaller during compilation.

For open-source distribution, the preferred path is SignPath Foundation. If
Prism needs a paid managed certificate later, Azure Artifact Signing is the
lowest-friction option where available.
