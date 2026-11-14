KAI BRIDGE INSPECTION v5.2.0 - INSTALLER PACKAGE
================================================

WINDOWS
1. Install Python 3.12 x64 on the build computer.
2. Install Inno Setup 6 or 7 to create the graphical Setup.exe.
3. Double-click BUILD_WINDOWS_INSTALLER.bat.
4. Collect the generated files from the release folder.

LINUX
1. Install Python 3.12, python3-venv, and dpkg-deb/dpkg-dev.
2. Run: ./BUILD_LINUX_INSTALLER.sh
3. Collect the generated files from the release folder.

End users do not need Python or pip. PyInstaller bundles the Python runtime
and application dependencies. Windows and Linux installers must be built on
their matching operating systems.

Detailed documentation: packaging/BUILD_INSTALLERS.md
