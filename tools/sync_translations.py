"""Generate QML JavaScript dictionaries from the editable JSON translations."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
I18N_DIR = ROOT / "src" / "kai_bridge_inspection" / "qml" / "i18n"


def render_js(payload: dict[str, object]) -> str:
    encoded = json.dumps(payload, ensure_ascii=False, indent=2)
    return f".pragma library\n\nvar strings = {encoded};\n"


def main() -> int:
    for json_path in sorted(I18N_DIR.glob("*.json")):
        payload = json.loads(json_path.read_text(encoding="utf-8"))
        json_path.with_suffix(".js").write_text(render_js(payload), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
