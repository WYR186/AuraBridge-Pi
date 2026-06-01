# WirePlumber Versioning

## Hard rule

**Always check the installed WirePlumber version first.** WirePlumber changed
its configuration model between the 0.4.x and 0.5.x series. A config written for
one will not work on the other. Copying examples from "the latest docs" onto an
older install (or vice versa) is a common, time-wasting failure.

Run:

```bash
./scripts/wireplumber-version-check.sh
```

It prints the PipeWire and WirePlumber versions, the likely config model, and
the config directories that exist on this machine. It makes **no changes.**

## The two config models

| WirePlumber version | Config model | Where |
| --- | --- | --- |
| **0.4.x** | **Lua** scripts/rules | `/usr/share/wireplumber/`, `/etc/wireplumber/`, `~/.config/wireplumber/` (`.lua`) |
| **0.5.x or newer** | **SPA-JSON** (`.conf` fragments) | `/usr/share/wireplumber/`, `/etc/wireplumber/wireplumber.conf.d/`, `~/.config/wireplumber/` (`.conf`) |

Rules:

- If WirePlumber is **0.4.x** → use 0.4 **Lua-style** configuration and 0.4-era
  documentation.
- If WirePlumber is **0.5.x+** → use the **SPA-JSON / JSON-style** model.
- Do **not** blindly copy the latest WirePlumber examples.
- Do **not** assume a 0.5.x config works on 0.4.x.
- Do **not** assume a 0.4.x Lua rule works on 0.5.x.

## Phase 0–3 policy: write nothing

**No WirePlumber policy or configuration file is created or modified in Phase
0–3.** This build only *detects and records* the version. Routing relies on
WirePlumber's default policy. Policy work (e.g. for Bluetooth routing or the
Safe Sink) belongs to later phases.

## When you do change policy later (documentation contract)

Any future WirePlumber configuration change must document:

- Installed WirePlumber version.
- Config directory used.
- Config syntax used (Lua vs SPA-JSON).
- Files modified.
- Reason for the change.
- Rollback instructions.

Record the version now (from `wireplumber-version-check.sh`) so the later phase
starts from a known baseline.
