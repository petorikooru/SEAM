# QML Modularization Audit

This audit covers every QML source file in `src/kai_bridge_inspection/qml`. The refactor prioritizes component boundaries that isolate reusable presentation, map interaction, chart interaction, form controls, and backend-facing orchestration.

## Refactor outcome

| View | Previous | Current | Result |
|---|---:|---:|---|
| `pages/Sensor.qml` | 1,504 | 408 | Converted to an orchestration page; chart, header, metrics, and map behavior moved into dedicated components. |
| `pages/Settings.qml` | 578 | 431 | MQTT broker management extracted into a self-contained settings component. |
| `dialogs/AddSensor.qml` | 491 | 377 | Shared field labels, broker selection, and step badges extracted. |
| `dialogs/AddLocation.qml` | 511 | 477 | Shared field labels and map buttons extracted. |
| `dialogs/SensorSettings.qml` | 663 | 526 | Shared labels, cards, rows, broker selection, and map controls extracted. |
| `pages/Location.qml` | 728 | 679 | Shared action buttons, metric cards, and map controls extracted. |

The source tree now contains 7,325 QML lines across 38 files, compared with 7,392 lines across 21 files in the previous package. The slight reduction in total lines is secondary to the main result: large views no longer contain multiple independent widgets and interaction engines in one file.

## Sensor-page architecture

`pages/Sensor.qml` owns only sensor loading, backend signal routing, chart registration, editing actions, and high-level layout. Its extracted modules are:

- `components/sensor/SensorHeaderCard.qml`: identity, status, and page actions.
- `components/sensor/SensorMetricsGrid.qml`: operational metric composition.
- `components/sensor/SensorMetricCard.qml`: individual metric presentation.
- `components/sensor/MotionChartPanel.qml`: title, right-aligned visible-series controls, top navigation toolbar, and chart slot.
- `components/sensor/MotionChart.qml`: Qt Charts series creation, live/frozen modes, panning, selection zoom, wheel zoom, and reset.
- `components/sensor/SeriesToggle.qml`: compact series visibility control.
- `components/sensor/SensorMapCard.qml`: sensor position and map navigation.

The accelerometer and inclinometer panels are independent vertical modules arranged in two page columns. Each panel keeps its visible-series controls in the title card and its navigation controls above the plot.

## Shared component inventory

| File | Responsibility | Audit decision |
|---|---|---|
| `common/WinButton.qml` | Standard text/icon button | Retained as the base button primitive. |
| `common/ActionButton.qml` | Compact page action button | Extracted from Location for reuse. |
| `common/IconButton.qml` | Icon-only action with tooltip | Retained; icon sizing now comes from Theme. |
| `common/WinTextField.qml` | Standard single-line input | Retained. |
| `common/WinTextArea.qml` | Standard multiline input | Retained. |
| `common/FieldLabel.qml` | Form field heading | Extracted and reused by dialogs. |
| `common/BrokerComboBox.qml` | Broker profile selector | Extracted and reused by Add Sensor and Sensor Settings. |
| `common/MapButton.qml` | Map navigation button | Extracted and reused by maps. |
| `common/SummaryCard.qml` | Operational summary card | Extracted and reused by Sensor Settings. |
| `common/MetricBox.qml` | Compact labeled metric | Extracted from Location. |
| `common/DataRow.qml` | Label/value diagnostic row | Extracted and reused by Sensor Settings. |
| `common/StepBadge.qml` | Numbered form section marker | Extracted from Add Sensor. |

## Full QML file review

### Application shell

| File | Lines | Assessment |
|---|---:|---|
| `Main.qml` | 261 | Cohesive application/window shell. The local window-control component is private to the custom title bar and does not justify a public component yet. |
| `Sidebar.qml` | 571 | Navigation-specific components remain local because they depend heavily on sidebar collapsed state, context menus, and tree expansion. A future split into `SidebarNavButton`, `SidebarSearch`, and `SidebarContextMenus` is feasible if the navigation model is moved to a dedicated data model. |
| `Theme.qml` | 91 | Appropriate singleton boundary. Centralizes dimensions, typography, colors, and icon sizes. |
| `Icons.qml` | 64 | Appropriate singleton boundary. Provides semantic Nerd Font glyphs and Unicode fallbacks. |
| `I18n.qml` | 49 | Appropriate runtime localization service boundary. |

### Pages

| File | Lines | Assessment |
|---|---:|---|
| `pages/Dashboard.qml` | 745 | Largest remaining page. Its location card and toolbar are dashboard-specific; extraction is possible after the location data structure is formalized as a QML model. Map interaction is already isolated conceptually but remains inline because it shares page filtering and marker selection state. |
| `pages/Location.qml` | 679 | Reduced through shared actions, metric cards, and map buttons. Remaining layout is location-specific and coordinates sensor selection, live charts, editing, and map state. |
| `pages/Settings.qml` | 431 | Page-level settings orchestration. MQTT broker CRUD has been extracted. Additional sections can be split later if their backend settings APIs become independent. |
| `pages/Sensor.qml` | 408 | Fully converted to orchestration plus two-column composition. |
| `pages/NodeRed.qml` | 310 | Cohesive embedded-browser/configuration view. Its local toolbar button is a small Node-RED-specific sizing variant. |

### Dialogs

| File | Lines | Assessment |
|---|---:|---|
| `dialogs/SensorSettings.qml` | 526 | Reduced with common cards, data rows, fields, broker selector, and map controls. Remaining content is one sensor-settings workflow. |
| `dialogs/AddLocation.qml` | 477 | Map placement and location form remain in one transactional workflow; shared primitives extracted. |
| `dialogs/HistoryChartDialog.qml` | 410 | Historical query, metric/range controls, and chart are tightly coupled. Its local combo style is dialog-specific but may become a common styled combo if another view requires it. |
| `dialogs/AddSensor.qml` | 377 | Reduced to the two-step creation workflow using shared form primitives. |

### Domain components

| File | Lines | Responsibility |
|---|---:|---|
| `components/settings/MqttBrokerSection.qml` | 303 | Broker list, editing, creation, usage counts, deletion guard, and blocked-deletion dialog. |
| `components/sensor/MotionChart.qml` | 256 | Reusable chart engine. |
| `components/sensor/SensorHeaderCard.qml` | 173 | Sensor identity and actions. |
| `components/sensor/MotionChartPanel.qml` | 165 | Motion-series header, toolbar, and chart host. |
| `components/DaemonPanel.qml` | 118 | Daemon control/status. |
| `components/sensor/SensorMapCard.qml` | 112 | Sensor map and gestures. |
| `components/MetricTile.qml` | 101 | Dashboard metric tile. |
| `components/sensor/SensorMetricCard.qml` | 77 | Sensor operational metric. |
| `components/sensor/SensorMetricsGrid.qml` | 69 | Sensor metric layout. |
| `components/StatusPill.qml` | 41 | Compact state indicator. |
| `components/sensor/SeriesToggle.qml` | 40 | Series checkbox/toggle. |
| `components/SectionHeader.qml` | 33 | Standard page section header. |

## Broker deletion guard

Deletion protection is enforced at two levels:

1. `MqttBrokerSection.qml` shows an error dialog containing the assigned sensor names when deletion is blocked.
2. `SettingsRepository.delete_broker()` independently rejects deletion whenever the broker is still referenced. This prevents orphaning even when deletion is invoked outside the QML UI.

`BackendController.getMqttBrokers()` exposes `sensor_count` and `sensor_names`, and `deleteMqttBroker()` returns a structured result so the QML layer does not infer failure from notifications.

## Component-boundary rules

- Pages coordinate data and navigation; they should not implement reusable controls or chart engines.
- Dialogs own one transaction and compose shared form primitives.
- Domain components may know sensor or broker concepts but should expose signals rather than navigate directly.
- Common components must not call backend methods.
- Theme, Icons, and I18n remain singleton services.
- Backend guardrails must also exist below QML when data integrity is involved.
