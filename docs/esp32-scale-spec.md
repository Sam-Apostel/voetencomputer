# DIY BLE Scale — Build Spec

Target: an ESP32 + HX711 scale that talks to **Voetencomputer** (iOS) over standard
Bluetooth, runs from batteries for years, and needs no Home Assistant.

Protocol: **Bluetooth SIG Weight Scale Service (0x181D)** — the open standard, not
Medisana's proprietary layout. Doing it this way means the scale also works with other
standards-compliant apps.

> **Status:** the app currently speaks only the Medisana protocol. 0x181D support is on
> Sam's side and not built yet. Build and test the firmware against a generic BLE tool
> (nRF Connect) first — app support lands after.

---

## 1. BLE interface

### 1.1 Advertising

| Item | Value |
|---|---|
| Service UUID in adv. packet | `0x181D` (**required** — the app scans for this) |
| Local name | free text, e.g. `Voetencomputer` |
| Address type | public / static (must be stable across reboots) |
| Interval, first 30 s after wake | 20–50 ms |
| Advertise window | 30 s after a weigh-in, then sleep |

Advertise **only while awake**. The phone keeps a pending connection open and will
connect within a second or two of the advertisement starting.

### 1.2 Services

| Service | UUID | Required |
|---|---|---|
| Weight Scale | `0x181D` | Yes |
| Battery | `0x180F` | Recommended |
| Device Information | `0x180A` | Optional |

### 1.3 Weight Scale Service characteristics

| Characteristic | UUID | Properties |
|---|---|---|
| Weight Measurement | `0x2A9D` | **Indicate** |
| Weight Scale Feature | `0x2A9E` | Read |

### 1.4 Weight Measurement (`0x2A9D`) payload

Little-endian. Fields appear in this order; optional fields only when their flag is set.

| Offset | Field | Type | Notes |
|---|---|---|---|
| 0 | Flags | uint8 | see below |
| 1–2 | Weight | uint16 | **unit = 0.005 kg** (SI) |
| +7 | Time Stamp | Date Time | only if flag bit 1 |
| +1 | User ID | uint8 | only if flag bit 2 |
| +2, +2 | BMI, Height | uint16 ×2 | only if flag bit 3 |

**Flags byte**

| Bit | Meaning | 0 | 1 |
|---|---|---|---|
| 0 | Units | SI (kg) | Imperial (lb) |
| 1 | Time stamp | absent | present |
| 2 | User ID | absent | present |
| 3 | BMI + height | absent | present |
| 4–7 | reserved | 0 | — |

**Date Time (7 bytes, if used):** uint16 year (LE), uint8 month 1–12, uint8 day 1–31,
uint8 hour 0–23, uint8 minute, uint8 second.

**Encoding example** — 80.0 kg, no optional fields:

```
80.0 / 0.005 = 16000 = 0x3E80
payload: 00 80 3E
         ^  ^^^^^
      flags  weight (LE)
```

### 1.5 Weight Scale Feature (`0x2A9E`)

uint32, read-only, describes capabilities.

| Bit(s) | Meaning |
|---|---|
| 0 | Time stamp supported |
| 1 | Multiple users supported |
| 2 | BMI supported |
| 3–6 | Weight resolution |
| 7–9 | Height resolution |

Weight resolution codes: `3` = 0.1 kg, `4` = 0.05 kg, `6` = 0.01 kg, `7` = 0.005 kg.

**Phase 1 value:** `0x00000018` (0.1 kg resolution, no timestamp/multi-user/BMI).
Declare the resolution the scale *actually* achieves — the payload encoding stays
0.005 kg per count regardless.

### 1.6 Timestamps — skip them

**Phase 1: leave flag bit 1 clear and send no timestamp.** The scale advertises
immediately after a weigh-in, so the phone receives the measurement live and stamps it
on arrival. This means **no RTC, no clock sync, no drift** — a large simplification.

Only add timestamps (and a custom time-set characteristic) if you later want the scale
to queue measurements taken while no phone was nearby.

### 1.7 Battery Service (recommended)

`0x180F` → Battery Level `0x2A19`, uint8 percent, read + notify. Cheap to implement and
means the app can warn before the batteries die.

---

## 2. Firmware behaviour

```
DEEP SLEEP  (HX711 powered down, ~30 µA total)
     │  GPIO wake (piezo / switch)
     ▼
WAKE        PD_SCK low → HX711 on
     │      wait 50 ms settling (@ 80 SPS)
     ▼
MEASURE     sample until stable:
     │      5 consecutive readings within ±50 g, and weight > 20 kg
     ▼
ADVERTISE   fast advertising, 30 s window
     │      on connect + CCCD subscribe → indicate 0x2A9D
     ▼
CONFIRM     await indication ACK, allow ~2 s, disconnect
     ▼
TARE        wait for step-off (< 5 kg), take zero reading,
     │      store tare + calibration in RTC slow memory
     ▼
SLEEP       PD_SCK high > 60 µs, then deep sleep
```

If no connection within the 30 s window: discard (Phase 1) or queue (Phase 2), sleep.

**Tare on the way out, not the way in.** You cannot zero the cells at wake — someone is
already standing on them. Taring after step-off, into RTC memory that survives deep
sleep, absorbs overnight thermal drift.

---

## 3. Hardware

### 3.1 Bill of requirements

| Item | Spec / note |
|---|---|
| MCU | ESP32 or ESP32-C3 **bare module** — not a dev board |
| ADC | HX711, channel A, gain 128 |
| Load cells | existing 4× half-bridge, wired as one Wheatstone bridge |
| Regulator | low quiescent: TPS7A02 (~25 nA) or MCP1700 (~1.6 µA) |
| Battery | 3× AA or 1× 18650 |
| Wake sensor | piezo disc, or tact switch under one foot pad |

**Do not use a dev board.** The USB-serial bridge, power LED and an AMS1117 regulator
(~5 mA quiescent) together burn more than everything else combined and will flatten the
battery in days. This is the single biggest determinant of battery life.

### 3.2 HX711 configuration

| Setting | Value | Why |
|---|---|---|
| Power-down | `PD_SCK` high > 60 µs | Sleeps the chip **and** cuts bridge excitation — this is what makes battery operation possible |
| Wake | `PD_SCK` low | Resets to channel A / gain 128 |
| RATE pin | tie **HIGH** = 80 SPS | Settling drops 400 ms → 50 ms. Cut the board's 10 SPS strap |
| Settling | 50 ms @ 80 SPS | Hidden behind the user's own wobble |
| Excitation | ~4.3 V from 5 V | At 3.3 V the regulator can't reach it; expect ~30% less signal (still ample). Adjust the AVDD divider if it matters |

Extra noise at 80 SPS is irrelevant: a body scale needs ~100 g over a 150 kg range,
far coarser than the chip delivers.

### 3.3 Wake circuit

**Option A — piezo disc (preferred, zero standby current)**

```
piezo ──┬── 100k ──┬── RTC GPIO (ext0 wake, active high)
        │          │
       1M      schottky clamps to 3V3 and GND
        │
       GND
```

Bond the disc under the platform. The 1 MΩ bleeds the charge, the series resistor plus
clamp diodes protect the pin from the piezo's voltage spike. Tune sensitivity so a
footstep on the floor nearby doesn't trigger it.

**Option B — tact switch** under one foot pad to GND, GPIO pull-up, ext0 wake active
low. Most robust, no false triggers, some mechanical fitting and eventual wear.

### 3.4 Power budget

| State | Current | Per day | mAh/day |
|---|---|---|---|
| Deep sleep | 30 µA | ~24 h | 0.72 |
| Weigh-in (BLE + HX711) | ~50 mA | 4 × 3 s | 0.17 |
| **Total** | | | **~0.9** |

A 2500 mAh pack is then limited by self-discharge rather than by the circuit —
realistically **2–3 years**. Sleep current dominates, so optimisation effort belongs in
the regulator and board choice, not in clever sensing.

---

## 4. Firmware platform

**ESPHome** — `esp32_ble_server` supports custom services and characteristics,
`on_write` handlers with lambdas, and notify via `ble_characteristic.set_value`. The
byte-packing lands in lambdas, so it's C++ in YAML clothing.

> ⚠️ **Verify before trusting any battery estimate:** does ESPHome's `hx711` platform
> power the chip down between reads? If it keeps the bridge energised, the entire
> power budget above is void and the HX711 must be driven manually.

**NimBLE-Arduino / ESP-IDF** — recommended if battery life matters. Lower RAM and flash,
noticeably faster boot (less energy per weigh-in), and direct control over indications
and sleep entry.

---

## 5. Acceptance checklist

Test with **nRF Connect** (iOS/Android) before involving the app.

- [ ] Advertisement contains service UUID `0x181D`
- [ ] `0x2A9E` reads back the expected feature word
- [ ] Subscribing to `0x2A9D` produces an indication within 2 s of stepping on
- [ ] Payload decodes: `raw × 0.005 = kg`, matches a known reference weight ±0.2 kg
- [ ] Deep sleep current measured < 50 µA (multimeter in µA range, battery in series)
- [ ] Wake → advertising in < 1 s
- [ ] 20 consecutive weigh-ins with no reboot or lockup
- [ ] Tare holds overnight (morning zero within ±0.3 kg)

---

## Appendix — constants

| Name | Value |
|---|---|
| Weight Scale Service | `0x181D` |
| Weight Measurement | `0x2A9D` (indicate) |
| Weight Scale Feature | `0x2A9E` (read) |
| Battery Service / Level | `0x180F` / `0x2A19` |
| Weight encoding (SI) | uint16, 0.005 kg per count |
| Phase 1 flags byte | `0x00` |
| Phase 1 feature word | `0x00000018` |
| HX711 power-down | `PD_SCK` high > 60 µs |
| HX711 settling @ 80 SPS | 50 ms |

### Future: body composition

If impedance electrodes are ever added, the matching standard is the **Body Composition
Service `0x181B`** (Body Composition Measurement `0x2A9C`), which carries fat %, muscle
%, muscle mass, water mass, BMR and impedance. Note it defines **no bone mass field** —
that one has no standard home.
