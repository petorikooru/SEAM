# AGENTS.md — SEAM contributor and coding-agent guide

## Project at a glance

SEAM (Structure Evaluation and Acquisition Monitoring) is a desktop bridge-inspection dashboard. The intended application stack is **Python 3.12+, PyQt6 with QML, and MySQL**. Node-RED owns MQTT connectivity and Sparkplug B decoding; the desktop receives validated `kai.telemetry.v1` JSON over a dedicated WebSocket endpoint for each sensor.

**Important current-state warning:** The repository currently documents and depends on **PySide6** and uses **SQLite**. PyQt6 and MySQL are the desired direction, not an already-completed migration. Do not silently treat the current README, tests, packaging, or existing databases as if they had already been migrated. When changing either stack component, update code, dependency metadata, tests, packaging, and documentation together; keep existing data safe.

## Where to work

- `src/kai_bridge_inspection/`: desktop Python package; `application/` contains startup code, `qml/` contains the interface, and `telemetry/`, `controllers/`, `models/`, and `settings/` contain related application logic.
- `nodered/`: Node-RED flow and Sparkplug decoder. See `nodered/README.md` before changing the ingest pipeline.
- `docs/architecture.md` and `docs/nodered-contract.md`: architecture and the canonical telemetry contract.
- `tests/`: regression coverage; `pyproject.toml`: Python dependencies, tooling, and package data; `packaging/`: distribution assets.

## Non-negotiable architecture boundaries

1. Keep MQTT connections, Sparkplug B protobuf decoding, aliases, and session state in Node-RED. Do not move them into the desktop runtime. Existing legacy MQTT modules are not permission to bypass this boundary.
2. Keep one WebSocket endpoint per sensor, carrying all of that sensor's metrics. Route widgets by `metric_name`, not by creating a WebSocket per widget.
3. Validate schema, payload types, timestamps, and the match between configured endpoint and `device_id` before persisting. Reject malformed or mismatched batches; do not partially save an invalid batch.
4. Preserve the `kai.telemetry.v1` contract unless the coordinated Node-RED, desktop, docs, and tests changes explicitly introduce a versioned replacement.
5. Keep the GUI responsive: WebSocket handling, database queries/writes, and exports must not block the QML/GUI thread. Bound queues and handle disconnected sensors independently.

## Database direction: MySQL

- Use **MySQL** for application persistence going forward. The existing SQLite storage, including `settings.db`, must be treated as legacy state requiring an explicit, tested migration plan; do not delete or overwrite user data.
- Keep SQL and connection management in a persistence/repository layer; QML must not execute SQL or hold database credentials. Use parameterized queries and transactions for related writes.
- Store credentials outside source control, for example in environment variables or a local ignored configuration file; never log passwords or connection strings containing secrets. Provide a documented local-development configuration when implementing the migration.
- Define schema changes as repeatable, versioned migrations. Specify how existing sensor settings and telemetry are copied from SQLite, how duplicates and failed migrations are handled, and how to verify row counts and representative records before retiring the old store.
- Preserve nanosecond telemetry timestamps without floating-point conversion or loss of precision. Document timestamp format, time zone conventions, indexes, and retention assumptions.
- Tests should use isolated MySQL fixtures or a disposable test database for integration coverage; unit tests should not require a live production database. Do not claim MySQL support is complete until startup, reads, writes, history, and packaging have been exercised.

## UI direction: PyQt6 + QML

- Use **PyQt6** for new desktop Qt bindings and QML for the UI. Do not mix PyQt6 and PySide6 objects in one running application.
- Migrate imports, signals/slots, properties, models, QML registration, dependency declarations, bundling hooks, and tests as one coherent change. Check PyQt6 API differences rather than mechanically renaming imports.
- Keep business logic, input validation, and persistence in Python; expose small, documented Qt models/properties/slots to QML. Keep QML focused on presentation and user interaction.
- Update `pyproject.toml`, `uv.lock` if used, launch instructions, and packaging scripts when changing the binding. Verify all QML files and assets still ship in the installed application.

## Working conventions

- Follow existing package structure and style rather than introducing a parallel architecture. Add type hints to Python code and focused tests for behavior changes.
- Prefer small, reviewable changes. For migrations, document the rollout and backward-compatibility decision before removing legacy code or data paths.
- Do not commit secrets, generated build artifacts, user databases, or real sensor telemetry. Use synthetic fixtures for tests.
- Keep README and architecture docs aligned with the actual implementation; distinguish the *target stack* from what currently runs.

## Validation

Run relevant checks after changes (install development dependencies first):

python -m compileall -q src tests main.py
pytest -q
ruff check .
mypy src
node --check nodered/node-red-contrib-kai-sparkplug/nodes/kai-sparkplug-decode.js
python -m json.tool nodered/flows/spbv1.0-kai-bridge.json > /dev/null

Also run a desktop startup/QML smoke test when changing UI or packaging, and a disposable-MySQL integration test when changing persistence. If a check cannot run in the current environment, state that explicitly rather than claiming it passed.
