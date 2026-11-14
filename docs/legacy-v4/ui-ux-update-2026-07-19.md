# UI/UX Workflow Update — 2026-07-19

## Visual system

- Restored the operational orange accent and refined the dark-surface hierarchy, borders, dividers, focus states, and disabled states.
- Standardized field, button, card, status-pill, and dialog spacing.
- Removed the bundled font dependency; the desktop application now uses the operating-system UI font and standard Unicode symbols.

## Dashboard and map

- Corrected toolbar, view-toggle, search-field, card, marker, and map-control alignment.
- Restored wheel zoom, click-drag panning, pinch zoom, double-click focus, and explicit zoom/reset controls.
- Kept location-marker selection independent from map gestures.
- Added a visible location count and navigation hint inside the map surface.

## Add Sensor

- Reorganized the workflow into identity and telemetry-connection stages.
- Added broker profile details, endpoint context, clearer required-field validation, and location/GNSS guidance.
- Broker profiles refresh whenever the dialog opens.

## Add Location

- Rebuilt the dialog as a details-and-map workspace.
- Added address search, coordinate feedback, direct map placement, map navigation controls, and clearer save validation.

## Sensor Settings

- Added operational summary cards for MQTT state, battery, signal, sample rate, data latency, and lost samples.
- Grouped broker/topic configuration, device identity, active metrics, GNSS position, and pipeline diagnostics by task.
- Restored full map interaction for sensor-position editing.

## Sensor telemetry

- Accelerometer and inclinometer views now use a responsive side-panel layout: metric controls and series selectors on the left, graph on the right.
- Narrow windows fall back to a vertical layout without clipping.

## Location page

- Rebuilt the page around an always-available navigable map, site overview cards, sensor selection, selected-sensor metrics, and live telemetry charts.
- Editing location metadata no longer removes map navigation.

## Node-RED

- Added an endpoint/status toolbar, reload action, host/port validation, and a slide-in connection panel while retaining the embedded editor.

## Validation

- Automated tests: 20 passed.
- QML application launch and navigation verified in an offscreen 1320×820 run.
- The modified application entrypoint passed Ruff; Python compilation completed successfully.
