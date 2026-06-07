# AuraBridge Dashboard

First read-only web dashboard for AuraBridge Pi.

The dashboard is intentionally dependency-light:

- Static frontend: `index.html`, `styles.css`, `app.js`
- Demo/API data: `data/status.sample.json`
- Optional preview server: `server.py` using only Python standard library

## Run locally

```bash
cd dashboard
python3 server.py
```

Open:

```text
http://127.0.0.1:8080
```

On the Raspberry Pi LAN, bind to all interfaces:

```bash
cd dashboard
python3 server.py --host 0.0.0.0 --port 8080
```

Then open `http://<pi-ip>:8080` from another device on the same Wi-Fi.

## Current scope

This first version is read-only. It does not restart services, change outputs,
open Bluetooth pairing, enable DLNA, or run arbitrary shell commands.

`/api/status` currently serves sample data with a live timestamp. The next step
is a small collector that converts existing scripts and systemd state into this
same JSON shape.
