# Daemon lifecycle

States: `STOPPED`, `STARTING`, `IDLE`, `CONNECTING`, `RUNNING`, `PAUSED`, `RECONNECTING`, `STOPPING`, and `FAILED`.

```text
STOPPED → STARTING → IDLE → CONNECTING → RUNNING
                         ↘ PAUSED ←─────┘
RUNNING → RECONNECTING → RUNNING
any active state → STOPPING → STOPPED
recoverable FAILED → STARTING
```

`IDLE` means the process and IPC server are running but collection has not started. `PAUSED` means collection was disabled or no enabled brokers are available. `RUNNING` requires at least one connected broker. Broker loss moves the daemon to `RECONNECTING` while paho applies bounded exponential reconnect delays.

Startup acquires a JSON lock containing PID, random token, Python executable, and expected module identity. Linux stale checks also verify `/proc/<pid>/cmdline`. QLocalServer removes only a stale endpoint after the instance lock succeeds.

Graceful shutdown disconnects MQTT, stops the processor cooperatively, flushes and joins the writer, checkpoints WAL, closes IPC, releases the lock, and exits the Qt event loop. The desktop force-kills only a managed child after a graceful timeout.
