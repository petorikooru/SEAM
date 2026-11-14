# KAI Bridge Inspection v5.2.0 installer build

The generated bundle contains only the desktop application. End users do not need Python or PySide6. MQTT and Sparkplug dependencies are intentionally absent because Node-RED is deployed and maintained separately.

PyInstaller is not a cross-compiler; build on the target operating system.

## Windows x64

Requirements: Windows 10/11 x64, Python 3.12 x64, and optionally Inno Setup 6 or 7 for `Setup.exe`.

```powershell
packaging\windows\build.bat -Clean
```

Outputs in `release/`:

- `KAI_Bridge_Inspection_v5.2.0_Windows_x64_Setup.exe`
- `KAI_Bridge_Inspection_v5.2.0_Windows_x64_Portable.zip`

## Linux x86_64

Requirements: a recent Linux distribution, Python 3.12, `dpkg-deb` for `.deb`, and optionally `appimagetool`.

```bash
./packaging/linux/build.sh --clean
```

Outputs in `release/` are a portable `.tar.gz`, a `.deb` when `dpkg-deb` is available, and an AppImage when `appimagetool` is available.

## Deployment boundary

The installer does not install Node-RED, the MQTT broker, or the custom Sparkplug node. Deploy those operational components using `nodered/README.md`, then configure the desktop host, port, and the WebSocket paths for each sensor profile.

Application databases and logs remain in the platform-specific user-data directory and are preserved during normal upgrades.
