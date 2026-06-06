#!/usr/bin/env bash
set -euo pipefail

# check-ka11.sh — Phase 1: validate the FiiO KA11 USB DAC.
#
# Detects the KA11 / USB DAC DYNAMICALLY by name across lsusb, ALSA cards, and
# PipeWire/PulseAudio sinks. It NEVER assumes the KA11 is ALSA card 1 or device 0.
# Prints a PASS / WARN / FAIL summary. Exits non-zero only on FAIL (KA11 not
# detected as a USB audio device at all). See docs/ka11-validation.md.

# Case-insensitive hints used to recognize the KA11 / a USB DAC.
HINTS='fiio|ka11|meizu|usb audio|usb-audio|\bdac\b|headphone|usb dac'

have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n===== %s =====\n' "$*"; }

usb_found=0
alsa_found=0
sink_found=0
pw_running=0
declare -a USB_CARDS=()   # dynamically detected ALSA card indexes

section "lsusb (USB devices)"
if have lsusb; then
  lsusb || true
  if lsusb 2>/dev/null | grep -iE "$HINTS" >/dev/null 2>&1; then
    usb_found=1
    echo
    echo ">> USB DAC hint matched:"
    lsusb 2>/dev/null | grep -iE "$HINTS" || true
  fi
else
  echo "(lsusb not available — install 'usbutils' via setup-base.sh)"
fi

section "aplay -l (ALSA playback sound cards)"
if have aplay; then
  aplay -l 2>/dev/null || echo "(aplay -l reported no cards)"
  # Parse 'card N: <id> [<name>], device ...' lines that look like USB audio.
  while IFS= read -r line; do
    if printf '%s' "$line" | grep -iE "$HINTS" >/dev/null 2>&1; then
      cardnum="$(printf '%s' "$line" | sed -nE 's/^card ([0-9]+):.*/\1/p')"
      if [[ -n "$cardnum" ]]; then
        alsa_found=1
        # de-dupe
        if ! printf '%s\n' "${USB_CARDS[@]:-}" | grep -qx "$cardnum" 2>/dev/null; then
          USB_CARDS+=("$cardnum")
        fi
      fi
    fi
  done < <(aplay -l 2>/dev/null | grep -E '^card [0-9]+:' || true)
  if [[ "${#USB_CARDS[@]}" -gt 0 ]]; then
    echo
    echo ">> Detected likely USB DAC ALSA card index(es): ${USB_CARDS[*]}"
  fi
else
  echo "(aplay not available — install 'alsa-utils' via setup-base.sh)"
fi

section "aplay -L (ALSA PCM names)"
if have aplay; then
  aplay -L 2>/dev/null | grep -iE "$HINTS" -A0 || echo "(no USB-DAC-like PCM names matched; full list suppressed)"
else
  echo "(aplay not available)"
fi

section "ALSA mixer controls for detected USB card(s)"
if have amixer && [[ "${#USB_CARDS[@]}" -gt 0 ]]; then
  for c in "${USB_CARDS[@]}"; do
    echo "--- amixer -c ${c} scontrols ---"
    if amixer -c "$c" scontrols 2>/dev/null; then
      :
    else
      echo "(no simple mixer controls on card ${c} — volume likely handled in the PipeWire graph)"
    fi
  done
else
  echo "(amixer unavailable or no USB card detected — skipping mixer dump)"
fi

section "PipeWire / WirePlumber versions"
if have pipewire;    then echo "pipewire:    $(pipewire --version 2>/dev/null | head -n1)"; else echo "pipewire:    (not installed)"; fi
if have wireplumber; then echo "wireplumber: $(wireplumber --version 2>/dev/null | head -n1)"; else echo "wireplumber: (not installed)"; fi

section "wpctl status (PipeWire graph)"
if have wpctl; then
  if wpctl status 2>/dev/null; then
    pw_running=1
  else
    echo "(wpctl could not reach a PipeWire session — is it running for this user?)"
  fi
else
  echo "(wpctl not available — install 'wireplumber')"
fi

section "pactl list sinks short (PulseAudio-API sinks)"
if have pactl; then
  if pactl list sinks short 2>/dev/null; then
    pw_running=1
    if pactl list sinks short 2>/dev/null | grep -iE "$HINTS" >/dev/null 2>&1; then
      sink_found=1
      echo
      echo ">> USB/FiiO-like sink matched:"
      pactl list sinks short 2>/dev/null | grep -iE "$HINTS" || true
    fi
  else
    echo "(pactl could not reach pipewire-pulse — is it running?)"
  fi
else
  echo "(pactl not available — install 'pulseaudio-utils')"
fi

# Also consider a wpctl sink match if pactl missed it.
if [[ "$sink_found" -eq 0 ]] && have wpctl; then
  if wpctl status 2>/dev/null | grep -iE "$HINTS" >/dev/null 2>&1; then
    sink_found=1
  fi
fi

# ---- Summary ------------------------------------------------------------
section "SUMMARY"
echo "USB enumeration (lsusb hint) : $([[ $usb_found -eq 1 ]] && echo yes || echo no)"
echo "ALSA card (aplay -l hint)    : $([[ $alsa_found -eq 1 ]] && echo "yes (card(s): ${USB_CARDS[*]:-none})" || echo no)"
echo "PipeWire session reachable   : $([[ $pw_running -eq 1 ]] && echo yes || echo no)"
echo "PipeWire/Pulse sink hint     : $([[ $sink_found -eq 1 ]] && echo yes || echo no)"
echo

if [[ "$usb_found" -eq 0 && "$alsa_found" -eq 0 ]]; then
  echo "RESULT: FAIL — KA11 / USB DAC was not detected as a USB audio device."
  echo "        Stop here and fix the hardware path (adapter, USB port, power)."
  echo "        See docs/hardware.md and TROUBLESHOOTING.md."
  exit 1
fi

if [[ "$usb_found" -eq 1 && "$alsa_found" -eq 1 && "$sink_found" -eq 1 ]]; then
  echo "RESULT: PASS — KA11 detected at USB, ALSA, and PipeWire layers."
  echo "        Next: ./scripts/safe-volume.sh, then a LOW-volume playback test."
  exit 0
fi

echo "RESULT: WARN — KA11 detected at some layers but not all."
if [[ "$pw_running" -eq 0 ]]; then
  echo "        PipeWire session not reachable yet. Run ./scripts/setup-pipewire.sh,"
  echo "        ensure: systemctl --user status pipewire wireplumber pipewire-pulse,"
  echo "        then re-run this check."
else
  echo "        The DAC is present but not yet visible as a PipeWire sink."
  echo "        Check 'wpctl status' and re-run after a moment."
fi
echo "        (Not a hard failure — resolve before playback.)"
exit 0
