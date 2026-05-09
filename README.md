# SumoBot ESP32 — WiFi Controlled Combat Robot

A WiFi-controlled sumo robot built with an ESP32, dual BTS7960 (IBT_2) motor drivers, and a custom Flutter mobile controller. Four firmware variants are included so you can pick the control mode that fits your environment — from a built-in web UI to a low-latency UDP Access Point mode for the arena.

---

## Kelompok / Team Members

| No | Nama                                       | NIM         |
|----|--------------------------------------------|-------------|
| 1  | Anak Agung Gde Weida Ksatriawarma          | 230010002   |
| 2  | Vincent Alfian Artha                       | 230010009   |
| 3  | ANAK AGUNG NGURAH BAJRA DIPA NAROTAMA      | 230010037   |
| 4  | I Kadek Danda Permana                      | 230010066   |
| 5  | Joshua Caleb Abril                         | 230010041   |

---

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Hardware Requirements](#hardware-requirements)
4. [Wiring Diagram](#wiring-diagram)
5. [Firmware Variants](#firmware-variants)
6. [Installation & Setup](#installation--setup)
7. [Mobile App (SumoBot Controller)](#mobile-app-sumobot-controller)
8. [Command Reference](#command-reference)
9. [Project Structure](#project-structure)
10. [How It Works](#how-it-works)
11. [Troubleshooting](#troubleshooting)
12. [Safety Notes](#safety-notes)

---

## Overview

This project implements a Bluetooth/WiFi-style remote-controlled sumo robot platform on the ESP32 microcontroller. The bot uses two DC gear motors driven by BTS7960 (IBT_2) H-bridge modules to deliver high torque suitable for combat sumo competitions.

The ESP32 hosts the control endpoint — depending on the firmware loaded, that can be:

- An HTTP **web server** with an embedded HTML D-Pad UI (no app needed),
- A **UDP listener** in Station mode (joins your home WiFi for fast, low-jitter commands),
- A **UDP listener in Access Point mode** (the bot itself becomes the WiFi network — best for arenas with no router).

A companion Flutter mobile app (`sumo-mobile/`) provides a polished controller UI on Android.

---

## Features

- **Tank-style differential drive** — independent control of left and right motor pairs
- **Full directional control** — forward (maju), backward (mundur), pivot left (kiri), pivot right (kanan), stop
- **PWM speed control (0–255)** — runtime-adjustable motor duty cycle via `spd:N` / `pwm:N` UDP commands; mobile app exposes a live PWM panel with frequency, resolution, and duty %
- **Hardware PWM via LEDC** — selectable frequency (1 kHz, 5 kHz, 20 kHz) at 8-bit resolution; 20 kHz mode keeps motors silent (above audible range)
- **Ultrasonic distance sensor (HC-SR04)** — front-mounted obstacle / enemy detection with `dist` command returning centimeters; mobile app shows live RADAR card with LOCK-ON / TARGET / CLEAR states
- **PWM telemetry** — `info` command reports `freq`, `duty`, `res`, `max` so the controller app can show live PWM configuration
- **Three connectivity modes** — HTTP Web UI, UDP Station, UDP Access Point
- **Safety watchdog** — auto-stop if no command received within 300 ms (UDP variants)
- **Status LED feedback** — blinks when idle, solid when phone connected (AP mode)
- **Custom Flutter mobile app** — D-Pad interface with hold-to-move, release-to-stop, PWM speed slider (0–255), live ultrasonic radar
- **Pre-built APK included** — `SumoBot.apk` for instant install

---

## Hardware Requirements

| Component                | Quantity | Notes                                               |
|--------------------------|---------:|-----------------------------------------------------|
| ESP32 DevKit V1 (38-pin) |        1 | Any ESP32 board with built-in WiFi                  |
| BTS7960 / IBT_2 driver   |        2 | One per motor, 43 A peak                            |
| DC gear motor (12 V)     |        2 | High-torque, recommended ≥ 200 RPM                  |
| LiPo battery 3S (11.1 V) |        1 | Or 12 V power source rated ≥ 5 A                    |
| Buck converter (LM2596)  |        1 | Step down 12 V → 5 V to power ESP32                 |
| Robot chassis            |        1 | Sumo-class (≤ 500 g, max 20×20 cm typical)          |
| Wheels (rubber)          |        2 | High grip                                            |
| Caster ball / skid       |        1 | Front balance point                                  |
| HC-SR04 ultrasonic sensor|        1 | Front-mounted, 5 V logic, ~2–400 cm range            |
| Jumper wires             |    ~20 |                                                     |
| Switch (rocker, 10 A)    |        1 | Master power switch                                  |

---

## Wiring Diagram

### ESP32 → BTS7960 (Right Motor)

| ESP32 Pin | BTS7960 Pin | Function          |
|-----------|-------------|-------------------|
| GPIO 26   | RPWM        | Right motor forward PWM |
| GPIO 25   | LPWM        | Right motor reverse PWM |
| 5 V       | VCC         | Logic supply      |
| GND       | GND         | Common ground     |
| 5 V       | R_EN, L_EN  | Enable both directions (tie HIGH) |

### ESP32 → BTS7960 (Left Motor)

| ESP32 Pin | BTS7960 Pin | Function          |
|-----------|-------------|-------------------|
| GPIO 27   | RPWM        | Left motor forward PWM |
| GPIO 14   | LPWM        | Left motor reverse PWM |
| 5 V       | VCC         | Logic supply      |
| GND       | GND         | Common ground     |
| 5 V       | R_EN, L_EN  | Enable both directions (tie HIGH) |

### ESP32 → HC-SR04 Ultrasonic Sensor

| ESP32 Pin | HC-SR04 Pin | Function          |
|-----------|-------------|-------------------|
| 5 V       | VCC         | Sensor power      |
| GND       | GND         | Common ground     |
| GPIO 5    | TRIG        | Trigger pulse out |
| GPIO 18   | ECHO        | Echo time-of-flight in |

> **Note:** The HC-SR04 ECHO pin outputs 5 V logic. Most ESP32 boards tolerate this on input pins, but for safety you may add a voltage divider (1 kΩ + 2 kΩ resistors) between ECHO and GPIO 18 to drop it to ~3.3 V.

### Power

```
[LiPo 12V] ─┬─→ BTS7960 Right (B+/B-)
            ├─→ BTS7960 Left  (B+/B-)
            └─→ LM2596 → 5 V ─┬→ ESP32 VIN
                              ├→ BTS7960 VCC (×2)
                              └→ HC-SR04 VCC
```

> **Important:** Run a thick wire (≥ 18 AWG) from battery to each driver. Keep ESP32 GND tied to driver GND and sensor GND.

---

## Firmware Variants

Four `.ino` sketches are provided. Pick the one that matches your environment:

| Sketch                                       | Mode         | Transport            | Best For                              |
|----------------------------------------------|--------------|----------------------|---------------------------------------|
| `firmware/sumo_http_sta/sumo_http_sta.ino`   | WiFi Station | HTTP                 | Quick test — control from any browser |
| `firmware/sumo_udp_sta/sumo_udp_sta.ino`     | WiFi Station | UDP (minimal)        | Low-latency play on home WiFi         |
| `firmware/sumo_main/sumo_main.ino`           | WiFi Station | UDP + full features  | Production with the Flutter app       |
| `firmware/sumo_ap/sumo_ap.ino`               | Access Point | UDP + full features  | Arena / no-router environments        |

> **Arduino IDE tip:** Each sketch lives in its own folder so the IDE can
> compile it cleanly. Open the `.ino` directly (e.g.
> `firmware/sumo_main/sumo_main.ino`) — don't try to open the parent
> `firmware/` folder.

### `sumo_http_sta.ino` — Web UI Mode
- Hosts an HTML D-Pad on port 80
- Open `http://<ESP32-IP>` in any phone browser
- Endpoints: `/maju`, `/mundur`, `/kiri`, `/kanan`, `/stop`
- Uses `analogWrite` for PWM (Arduino-friendly, ~5 kHz)

### `sumo_udp_sta.ino` — UDP Station (minimal)
- Connects to existing WiFi
- Listens on UDP port **4210**
- 300 ms safety watchdog: motors auto-stop if commands stop arriving
- Minimal reference implementation — for the full feature set use `sumo_main.ino`

### `sumo_main.ino` — UDP Station with PWM + Ultrasonic (production)
- Same as `sumo_udp_sta.ino` plus:
  - Dynamic PWM duty cycle: `spd:180` / `pwm:180` packet sets duty 0–255
  - HC-SR04 ultrasonic: `dist` packet returns `dist:NN` (cm) or `dist:-1` (no echo)
  - PWM telemetry: `info` packet returns `info:freq=20000,duty=N,res=8,max=255`
- 20 kHz PWM (silent operation, above audible range)
- Replies `ok` / `pong` / `spd:N` / `dist:N` / `info:...` so the app can sync state

### `sumo_ap.ino` — Access Point Mode (recommended for matches)
- ESP32 broadcasts WiFi SSID **`SumoBot`** (password: `sumo1234`)
- Bot IP is fixed: **`192.168.4.1`**
- LED status (GPIO 2): blinks 1 Hz when idle, solid when phone connected
- Full feature set: PWM speed control, ultrasonic distance, info reporting
- 1 kHz PWM (compatible with all BTS7960 clones)
- No router needed — perfect for tournaments

---

## Installation & Setup

### 1. Install Tools

- **Arduino IDE** 2.x — https://www.arduino.cc/en/software
- **ESP32 Board Package**:
  - File → Preferences → Additional Board Manager URLs:
    `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
  - Tools → Board → Boards Manager → search **"esp32"** → install (v3.0.0+ recommended)

### 2. Select Board

- Tools → Board → ESP32 Arduino → **ESP32 Dev Module**
- Tools → Upload Speed → **921600**
- Tools → Port → (select COM port of your ESP32)

### 3. Configure WiFi (STA Modes Only)

Open one of the STA-mode sketches and replace the placeholder credentials:

- `firmware/sumo_http_sta/sumo_http_sta.ino`
- `firmware/sumo_udp_sta/sumo_udp_sta.ino`
- `firmware/sumo_main/sumo_main.ino`

```cpp
const char* ssid     = "YOUR_WIFI_SSID";       // ← change
const char* password = "YOUR_WIFI_PASSWORD";   // ← change
```

For `firmware/sumo_ap/sumo_ap.ino`, the bot creates its own WiFi — no
configuration needed, but you can optionally rename the broadcast SSID
and password:

```cpp
const char* ap_ssid     = "SumoBot";
const char* ap_password = "sumo1234";   // min 8 characters (WPA2)
```

### 4. Upload

Click the **Upload** button (→ arrow). Watch the Serial Monitor at **115200 baud** to see the bot's IP address once connected.

---

## Mobile App (SumoBot Controller)

Two ways to use the mobile app:

### Option A — Install Pre-Built APK (Fastest)

1. Copy `SumoBot.apk` to your Android phone
2. Allow "Install from Unknown Sources" in settings
3. Tap to install
4. Connect phone to the same WiFi as the ESP32 (or to the `SumoBot` AP)
5. Tap the gear icon → enter the ESP32 IP shown in Serial Monitor (or `192.168.4.1` for AP mode)

### Option B — Build From Source (Flutter)

```bash
cd sumo-mobile
flutter pub get
flutter run --release
```

See `sumo-mobile/README.md` for full Flutter setup instructions.

### App Controls

- **Hold arrow** → robot moves in that direction
- **Release** → robot stops automatically
- **Center red button** → emergency stop
- **Gear icon** → set ESP32 IP

### App Panels

The mobile app exposes three live panels stacked vertically:

1. **RADAR card (top)** — real-time HC-SR04 distance
   - Polled every 250 ms via `dist` UDP packet
   - Color-coded state badge:
     - **CLEAR** (green) — distance > 50 cm
     - **TARGET** (amber) — 20 cm < distance ≤ 50 cm
     - **LOCK-ON** (red, glow) — distance ≤ 20 cm
     - **NO ECHO** (gray) — sensor returns -1 (out of range)
   - Animated fill bar (200 cm max scale)

2. **D-Pad (center)** — directional control with rounded buttons + center STOP

3. **PWM SPEED panel (bottom)** — pulse-width modulation control
   - Slider: 0 – 255 (51 divisions, sends `spd:N` on release)
   - Live readout: raw value (`200 / 255`) and duty cycle percentage (`78% duty`)
   - **FREQ pill** — current PWM frequency (e.g. `20 kHz`) read from firmware via `info`
   - **RES pill** — PWM resolution in bits (e.g. `8-bit`)

---

## Command Reference

All firmware variants accept the same core command vocabulary (sent as a UTF-8 string).
PWM speed, ultrasonic, and `info` commands are available in `sumo_main.ino` and `sumo_ap.ino`.

| Command  | Action                                              | Reply                            |
|----------|-----------------------------------------------------|----------------------------------|
| `maju`   | Move forward                                        | `ok`                             |
| `mundur` | Move backward                                       | `ok`                             |
| `kiri`   | Pivot / rotate left                                 | `ok`                             |
| `kanan`  | Pivot / rotate right                                | `ok`                             |
| `stop`   | Stop both motors                                    | `ok`                             |
| `ping`   | Connectivity check                                  | `pong`                           |
| `spd:N`  | Set PWM duty cycle (0–255). Alias of `pwm:N`        | `spd:N`                          |
| `pwm:N`  | Set PWM duty cycle (0–255). Alias of `spd:N`        | `spd:N`                          |
| `dist`   | Read HC-SR04 distance in cm                         | `dist:NN` or `dist:-1` (no echo) |
| `info`   | Report PWM configuration                            | `info:freq=N,duty=N,res=8,max=255` |

### Pin Configuration

```cpp
// === MOTOR PINS (PWM via LEDC) ===
// Right motor (BTS7960)
const int motorKananMaju   = 26;  // Forward / RPWM
const int motorKananMundur = 25;  // Reverse / LPWM

// Left motor (BTS7960)
const int motorKiriMaju    = 27;  // Forward / RPWM
const int motorKiriMundur  = 14;  // Reverse / LPWM

// === ULTRASONIC HC-SR04 ===
const int ULTRASONIC_TRIG  = 5;   // Trigger
const int ULTRASONIC_ECHO  = 18;  // Echo (consider 5 V → 3.3 V divider)

// === STATUS LED (AP mode only) ===
const int STATUS_LED       = 2;   // ESP32 onboard LED
```

### PWM Configuration

| Variant            | Frequency | Resolution | API used        |
|--------------------|-----------|------------|-----------------|
| `sumo_http_sta.ino`         | ~5 kHz    | 8-bit      | `analogWrite()` |
| `sumo_udp_sta.ino`     | ~5 kHz    | 8-bit      | `analogWrite()` |
| `sumo_main.ino`    | 20 kHz    | 8-bit      | `ledcAttach()` / `ledcWrite()` |
| `sumo_ap.ino`  | 1 kHz     | 8-bit      | `ledcAttach()` / `ledcWrite()` |

PWM duty cycle is always 0–255. Effective speed depends on motor + battery, but typical thresholds:
- **0–60** → motor stalls, no movement
- **60–120** → slow / creep
- **120–200** → cruise speed
- **200–255** → full attack speed

### HTTP Endpoints (sumo_http_sta.ino)

```
GET http://<ESP32-IP>/         → Web UI (D-Pad)
GET http://<ESP32-IP>/maju     → Forward
GET http://<ESP32-IP>/mundur   → Backward
GET http://<ESP32-IP>/kiri     → Pivot left
GET http://<ESP32-IP>/kanan    → Pivot right
GET http://<ESP32-IP>/stop     → Stop
```

---

## Project Structure

```
sumo-bot-real/
├── firmware/                           # ESP32 Arduino sketches (one per folder)
│   ├── sumo_http_sta/
│   │   └── sumo_http_sta.ino           # WiFi STA + HTTP web UI (browser controller)
│   ├── sumo_udp_sta/
│   │   └── sumo_udp_sta.ino            # WiFi STA + UDP (minimal reference)
│   ├── sumo_main/
│   │   └── sumo_main.ino               # WiFi STA + UDP + PWM + ultrasonic (production)
│   └── sumo_ap/
│       └── sumo_ap.ino                 # WiFi AP  + UDP + PWM + ultrasonic (no-router)
├── sumo-mobile/                        # Flutter controller app (source)
│   ├── lib/
│   │   └── main.dart
│   ├── android/
│   ├── pubspec.yaml
│   ├── preview.png
│   ├── preview-light.png
│   └── README.md
├── SumoBot.apk                         # Pre-built Android controller
├── .gitignore
└── README.md                           # This file
```

---

## How It Works

### Differential Drive Logic

The robot uses **tank-style steering** — by spinning the left and right wheels in different directions, it can pivot in place.

| Action      | Left Motor | Right Motor |
|-------------|------------|-------------|
| Forward     | Forward    | Forward     |
| Backward    | Backward   | Backward    |
| Pivot Left  | Backward   | Forward     |
| Pivot Right | Forward    | Backward    |
| Stop        | Off        | Off         |

### PWM (Pulse Width Modulation)

Motor speed is controlled by varying the PWM **duty cycle** while keeping the **frequency** constant. The ESP32 generates PWM in hardware via the **LEDC** peripheral, so timing is precise even when the CPU is busy with WiFi.

```
duty = 0       (0%)        ─────────────────────  motor off
duty = 64      (25%)       ▆▆▁▁▁▁▁▁▆▆▁▁▁▁▁▁▆▆▁▁  slow
duty = 128     (50%)       ▆▆▆▆▁▁▁▁▆▆▆▆▁▁▁▁▆▆▆▆  cruise
duty = 192     (75%)       ▆▆▆▆▆▆▁▁▆▆▆▆▆▆▁▁▆▆▆▆  fast
duty = 255     (100%)      ▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆▆  full power
```

**Frequency choice:**
- `sumo_main.ino`: 20 kHz — above human hearing, silent operation
- `sumo_ap.ino`: 1 kHz — safe for older / clone BTS7960 driver boards
- `sumo_http_sta.ino` and `sumo_udp_sta.ino`: ~5 kHz (default of `analogWrite` on arduino-esp32 v3)

**Setting duty cycle from the app:**
```
spd:200    → sets PWM duty to 200 (78% of max)
pwm:128    → sets PWM duty to 128 (50% of max) — alias for spd:
```

**Reading PWM state from the app:**
```
info       → bot replies: info:freq=20000,duty=200,res=8,max=255
```

The Flutter app sends `info` on connect and displays the returned frequency / resolution as live pills above the speed slider.

### Ultrasonic Distance Sensing

The HC-SR04 measures distance by:
1. ESP32 sends a 10 µs HIGH pulse on `TRIG`
2. Sensor emits an 8-cycle ultrasonic burst at 40 kHz
3. ECHO pin goes HIGH for the round-trip time of the reflection
4. Distance = `(echo_duration_us × 0.0343) / 2` cm

```cpp
long readDistanceCm() {
  digitalWrite(ULTRASONIC_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(ULTRASONIC_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(ULTRASONIC_TRIG, LOW);

  unsigned long duration = pulseIn(ULTRASONIC_ECHO, HIGH, 30000UL);
  if (duration == 0) return -1;          // no echo / out of range
  return (long)(duration * 0.0343 / 2.0);
}
```

The app polls `dist` every 250 ms when connected. The 30 ms `pulseIn` timeout caps the worst-case loop blocking — well below the 300 ms safety watchdog.

### Safety Watchdog (UDP variants)

If the ESP32 stops receiving commands for **300 ms**, it automatically stops the motors. This prevents runaway behavior if the phone disconnects mid-action.

```cpp
const unsigned long COMMAND_TIMEOUT_MS = 300;
if (motorRunning && (millis() - lastCommandAt > COMMAND_TIMEOUT_MS)) {
    stopMotor();
}
```

---

## Troubleshooting

| Problem                                  | Likely Cause / Fix                                                       |
|------------------------------------------|--------------------------------------------------------------------------|
| ESP32 won't connect to WiFi              | Check SSID/password, ensure 2.4 GHz network (ESP32 doesn't support 5 GHz) |
| Motors don't spin                        | Verify R_EN and L_EN on BTS7960 are tied to 5 V (always enabled)         |
| Motors spin in wrong direction           | Swap motor leads OR swap `Maju`/`Mundur` pin assignments                 |
| Commands work via browser but app fails  | Confirm UDP port 4210 isn't blocked by phone hotspot firewall            |
| Robot drifts when commanded forward      | Calibrate motors — slightly reduce PWM on the faster side via `spd:N`     |
| Bot stops randomly                       | Watchdog kicked in — phone may have lost WiFi briefly. Use AP mode.       |
| ESP32 resets when motors start           | Battery sag — separate logic supply (5 V regulator off battery)           |
| Whining noise from motors                | Use `sumo_main.ino` with 20 kHz PWM (above audible range)                 |
| HC-SR04 always returns `-1`              | Wire VCC to **5 V** (not 3.3 V); double-check TRIG=GPIO5, ECHO=GPIO18    |
| Distance reading is unstable             | Add a 10 µF cap across HC-SR04 VCC/GND, mount sensor away from motors    |
| App speed slider has no effect           | Make sure firmware is `sumo_main.ino` or `sumo_ap.ino` (not `sumo_udp_sta.ino`) |
| App shows `— Hz` in PWM panel            | Tap refresh — app sends `info` on connect; firmware must support `info`   |

---

## Safety Notes

- **Always test wheels-up first.** Block the chassis on a stand before powering up.
- **Use a master power switch** between battery and motor drivers.
- **Add an emergency stop.** The red center button in the app sends `stop` immediately.
- **Don't operate near pets or small children.** Sumo robots can deliver significant torque.
- **Disconnect battery before wiring changes.** BTS7960 modules can sink large currents into shorts.

---

## License & Acknowledgements

This project is built for educational purposes as a coursework project. Hardware is based on the open BTS7960 / IBT_2 motor driver reference design. ESP32 Arduino core: https://github.com/espressif/arduino-esp32

---

**SumoBot ESP32** — Built with ESP32, Flutter, and a lot of solder.
