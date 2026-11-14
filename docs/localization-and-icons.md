# Localization and Lucide icons

Select the interface language in **Settings → Language**. Edit the canonical
`qml/i18n/en.json` and `qml/i18n/id.json` dictionaries, keeping their keys in
sync. Run `python tools/sync_translations.py` to regenerate the JavaScript
dictionaries consumed by QML.

Use the semantic `Icons` registry with `LucideIcon`, or set `WinButton.iconName`
for a button with an icon and text. The bundled SVGs and license are in
`qml/assets/icons/lucide/`. The generated registry identifies the upstream
version and supplies local SVG markup for theme tinting.
