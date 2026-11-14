# Localization and icon fonts

The interface language is selected in **Settings → Language** and persisted through the existing settings backend.

Runtime translation files:

- `src/kai_bridge_inspection/qml/i18n/en.js`
- `src/kai_bridge_inspection/qml/i18n/id.js`

The JavaScript files contain plain dictionary objects and can be edited directly. Matching `.json` copies are included as editor-friendly references. Keep the key structure identical across languages. QML bindings use `I18n.t(...)` and `I18n.format(...)`, so changing the language updates bound text without restarting the application.

## Nerd Font icons

The application auto-detects a system-installed Nerd Font and uses its `nf-fa` / Font Awesome glyphs. Recognized families include `Symbols Nerd Font Mono`, `JetBrainsMono Nerd Font`, `FiraCode Nerd Font`, `Hack Nerd Font`, and `CaskaydiaCove Nerd Font` variants. When none is installed, semantic Unicode fallback symbols are used.

No font binary is bundled. Install a Nerd Font through the operating system and restart the application. The detected family or fallback status is shown in Settings.
## Editing translations

The canonical, human-editable files are `qml/i18n/en.json` and `qml/i18n/id.json`.
After editing either file, run:

```bash
python tools/sync_translations.py
```

This regenerates the small JavaScript dictionaries imported by the QML singleton.
The unit tests verify that both languages have identical key sets and that the generated
runtime files are synchronized.

## Optional local Nerd Font file

The application first searches installed families for an `nf-fa`-capable Nerd Font. It
also registers `.ttf` or `.otf` files placed in `qml/assets/fonts`, or paths provided by
`KAI_NERD_FONT_PATH`. The repository itself contains no font binary.

