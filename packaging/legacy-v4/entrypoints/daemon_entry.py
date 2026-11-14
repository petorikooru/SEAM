"""PyInstaller entry point for the independent telemetry daemon."""

from kai_bridge_inspection.daemon.__main__ import main

if __name__ == "__main__":
    raise SystemExit(main())
