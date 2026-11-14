# Sidebar Refresh and Broker Dialog Fix — 2026-07-19

## Sensor deletion sidebar refresh

Deleting a sensor changed the nested sensor list for a location but did not change the top-level list of location names. Existing QML delegates therefore retained their cached `getLocationData()` result until the application restarted.

`Main.qml` now increments `sidebarDataRevision` whenever the catalog changes. `Sidebar.qml` consumes that revision in its location and sensor data bindings, forcing the existing delegates to query the backend again without rebuilding the entire sidebar or losing expansion and scroll state.

## MQTT broker deletion guard popup

The broker guard previously used the native `Dialog` header and standard button footer. Depending on the platform control style, those areas were rendered with light system colors even while the application was in dark mode.

The guard is now a custom modal `Popup` with themed header, content, assigned-sensor list, close action, and footer. All surfaces use the application's active theme, while the primary acknowledgement action retains the orange accent with dark text.
