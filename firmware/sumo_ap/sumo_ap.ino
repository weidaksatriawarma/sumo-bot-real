/**
 * SumoBot ESP32 — Access Point Firmware (no-router mode)
 *
 * The ESP32 broadcasts its OWN WiFi network. The phone connects to that
 * SSID and reaches the bot at a fixed IP (192.168.4.1). No external
 * router required — perfect for arenas / tournaments.
 *
 * Full feature set:
 *   - Runtime-adjustable PWM duty cycle (0-255) via "spd:N" / "pwm:N"
 *   - HC-SR04 ultrasonic distance sensing via "dist"
 *   - PWM telemetry via "info"
 *   - 300 ms safety watchdog auto-stop
 *   - LED status: blink slow when idle, solid when phone connected
 *
 * Mode      : WiFi AP + UDP
 * Default   : SSID "SumoBot", password "sumo1234", IP 192.168.4.1
 * Commands  : maju, mundur, kiri, kanan, stop, ping, spd:N, pwm:N, dist, info
 * Hardware  : ESP32 + 2x BTS7960 (IBT_2) + 2x DC motors + HC-SR04
 * UDP port  : 4210
 * PWM       : 1 kHz, 8-bit (compatible with all BTS7960 / IBT_2 clones)
 *
 * Tim Kelompok:
 *   1. Anak Agung Gde Weida Ksatriawarma     (230010002)
 *   2. Vincent Alfian Artha                  (230010009)
 *   3. ANAK AGUNG NGURAH BAJRA DIPA NAROTAMA (230010037)
 *   4. I Kadek Danda Permana                 (230010066)
 *   5. Joshua Caleb Abril                    (230010041)
 */

#include <WiFi.h>
#include <WiFiUdp.h>

// ===== Access Point =====
// Phone connects to this SSID; bot IP is always 192.168.4.1
const char* ap_ssid     = "SumoBot";
const char* ap_password = "sumo1234";   // min 8 chars (WPA2)
const int   WIFI_CHANNEL = 1;            // usually the cleanest 2.4 GHz channel
const int   MAX_CLIENTS  = 1;            // only one phone at a time

// ===== Network =====
const uint16_t UDP_PORT = 4210;
WiFiUDP udp;
char packetBuffer[32];

// ===== Motor pins (BTS7960) =====
const int motorKananMaju   = 26;  // R RPWM
const int motorKananMundur = 25;  // R LPWM
const int motorKiriMaju    = 27;  // L RPWM
const int motorKiriMundur  = 14;  // L LPWM

// ===== Status LED (ESP32 onboard) =====
const int STATUS_LED = 2;

// ===== Ultrasonic (HC-SR04) =====
const int ULTRASONIC_TRIG = 5;
const int ULTRASONIC_ECHO = 18;
const unsigned long ULTRASONIC_TIMEOUT_US = 30000UL;  // ~5 m max range

// ===== PWM config =====
// 1 kHz is safe for all BTS7960 / IBT_2 driver boards (incl. clones).
const int PWM_FREQ       = 1000;
const int PWM_RESOLUTION = 8;      // 0-255
int speed = 200;                   // 0-255 — runtime adjustable via "spd:N"

// ===== Safety watchdog =====
const unsigned long COMMAND_TIMEOUT_MS = 300;
unsigned long lastCommandAt = 0;
bool motorRunning = false;

// ===== Heartbeat LED =====
unsigned long lastBlinkAt = 0;
bool ledState = false;

void setup() {
  Serial.begin(115200);

  // PWM via LEDC (hardware-timed)
  ledcAttach(motorKananMaju,   PWM_FREQ, PWM_RESOLUTION);
  ledcAttach(motorKananMundur, PWM_FREQ, PWM_RESOLUTION);
  ledcAttach(motorKiriMaju,    PWM_FREQ, PWM_RESOLUTION);
  ledcAttach(motorKiriMundur,  PWM_FREQ, PWM_RESOLUTION);

  pinMode(STATUS_LED, OUTPUT);
  digitalWrite(STATUS_LED, LOW);

  // HC-SR04 ultrasonic
  pinMode(ULTRASONIC_TRIG, OUTPUT);
  pinMode(ULTRASONIC_ECHO, INPUT);
  digitalWrite(ULTRASONIC_TRIG, LOW);

  stopMotor();

  Serial.println();
  Serial.println("===== SumoBot Access Point Mode =====");

  WiFi.mode(WIFI_AP);
  WiFi.setSleep(false);  // disable modem-sleep so latency stays stable
  bool ok = WiFi.softAP(ap_ssid, ap_password, WIFI_CHANNEL, 0, MAX_CLIENTS);
  if (!ok) {
    Serial.println("ERROR: Gagal membuat Access Point!");
    while (true) {
      digitalWrite(STATUS_LED, !digitalRead(STATUS_LED));
      delay(100);
    }
  }

  IPAddress ip = WiFi.softAPIP();
  Serial.print("SSID     : "); Serial.println(ap_ssid);
  Serial.print("Password : "); Serial.println(ap_password);
  Serial.print("Channel  : "); Serial.println(WIFI_CHANNEL);
  Serial.print("IP Bot   : "); Serial.println(ip);
  Serial.print("UDP Port : "); Serial.println(UDP_PORT);
  Serial.println();
  Serial.println("Cara pakai:");
  Serial.println("1. Di HP, connect ke WiFi \"SumoBot\"");
  Serial.println("2. Buka app Sumobot, masukkan IP: 192.168.4.1");
  Serial.println("3. Siap tanding!");
  Serial.println();
  Serial.println("Commands: maju|mundur|kiri|kanan|stop|ping|spd:N|pwm:N|dist|info");
  Serial.print("Default speed: "); Serial.println(speed);
  Serial.println("Ultrasonic HC-SR04: TRIG=GPIO5, ECHO=GPIO18");

  udp.begin(UDP_PORT);
}

void loop() {
  int packetSize = udp.parsePacket();
  if (packetSize) {
    IPAddress remoteIp   = udp.remoteIP();
    uint16_t  remotePort = udp.remotePort();
    int len = udp.read(packetBuffer, sizeof(packetBuffer) - 1);
    if (len > 0) {
      packetBuffer[len] = '\0';
      while (len > 0 && (packetBuffer[len - 1] == '\n' ||
                         packetBuffer[len - 1] == '\r' ||
                         packetBuffer[len - 1] == ' ')) {
        packetBuffer[--len] = '\0';
      }
      handleCommand(packetBuffer, remoteIp, remotePort);
      lastCommandAt = millis();
    }
  }

  // Safety watchdog
  if (motorRunning && (millis() - lastCommandAt > COMMAND_TIMEOUT_MS)) {
    stopMotor();
  }

  updateStatusLed();
}

void sendReply(const char* msg, IPAddress ip, uint16_t port) {
  udp.beginPacket(ip, port);
  udp.write((const uint8_t*)msg, strlen(msg));
  udp.endPacket();
}

void handleCommand(const char* cmd, IPAddress ip, uint16_t port) {
  if      (strcmp(cmd, "ping")   == 0) sendReply("pong", ip, port);
  else if (strcmp(cmd, "maju")   == 0) { gerakMaju();   sendReply("ok", ip, port); }
  else if (strcmp(cmd, "mundur") == 0) { gerakMundur(); sendReply("ok", ip, port); }
  else if (strcmp(cmd, "kiri")   == 0) { putarKiri();   sendReply("ok", ip, port); }
  else if (strcmp(cmd, "kanan")  == 0) { putarKanan();  sendReply("ok", ip, port); }
  else if (strcmp(cmd, "stop")   == 0) { stopMotor();   sendReply("ok", ip, port); }
  else if (strcmp(cmd, "dist")   == 0) {
    long d = readDistanceCm();
    char reply[16];
    if (d < 0) strcpy(reply, "dist:-1");
    else       snprintf(reply, sizeof(reply), "dist:%ld", d);
    sendReply(reply, ip, port);
  }
  else if (strncmp(cmd, "spd:", 4) == 0 || strncmp(cmd, "pwm:", 4) == 0) {
    int val = atoi(cmd + 4);
    if (val < 0)   val = 0;
    if (val > 255) val = 255;
    speed = val;
    char reply[16];
    snprintf(reply, sizeof(reply), "spd:%d", speed);
    sendReply(reply, ip, port);
  }
  else if (strcmp(cmd, "info") == 0) {
    // Report PWM configuration so the controller app can show it
    char reply[48];
    snprintf(reply, sizeof(reply),
             "info:freq=%d,duty=%d,res=%d,max=255",
             PWM_FREQ, speed, PWM_RESOLUTION);
    sendReply(reply, ip, port);
  }
}

// LED status:
//  - Idle (no phone connected): slow 1 Hz blink
//  - Phone connected: solid on
void updateStatusLed() {
  int clients = WiFi.softAPgetStationNum();
  unsigned long now = millis();

  if (clients > 0) {
    digitalWrite(STATUS_LED, HIGH);
  } else {
    if (now - lastBlinkAt > 500) {
      lastBlinkAt = now;
      ledState = !ledState;
      digitalWrite(STATUS_LED, ledState);
    }
  }
}

// ===== Motor control =====

void gerakMaju() {
  ledcWrite(motorKananMaju, 0);
  ledcWrite(motorKananMundur, speed);
  ledcWrite(motorKiriMaju, 0);
  ledcWrite(motorKiriMundur, speed);
  motorRunning = true;
}

void gerakMundur() {
  ledcWrite(motorKananMaju, speed);
  ledcWrite(motorKananMundur, 0);
  ledcWrite(motorKiriMaju, speed);
  ledcWrite(motorKiriMundur, 0);
  motorRunning = true;
}

void putarKanan() {
  ledcWrite(motorKananMaju, speed);
  ledcWrite(motorKananMundur, 0);
  ledcWrite(motorKiriMaju, 0);
  ledcWrite(motorKiriMundur, speed);
  motorRunning = true;
}

void putarKiri() {
  ledcWrite(motorKananMaju, 0);
  ledcWrite(motorKananMundur, speed);
  ledcWrite(motorKiriMaju, speed);
  ledcWrite(motorKiriMundur, 0);
  motorRunning = true;
}

void stopMotor() {
  ledcWrite(motorKananMaju, 0);
  ledcWrite(motorKananMundur, 0);
  ledcWrite(motorKiriMaju, 0);
  ledcWrite(motorKiriMundur, 0);
  motorRunning = false;
}

// ===== Ultrasonic (HC-SR04) =====
// Returns distance in cm, or -1 on no echo / out of range.
long readDistanceCm() {
  digitalWrite(ULTRASONIC_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(ULTRASONIC_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(ULTRASONIC_TRIG, LOW);

  unsigned long duration = pulseIn(ULTRASONIC_ECHO, HIGH, ULTRASONIC_TIMEOUT_US);
  if (duration == 0) return -1;
  // Speed of sound ~0.0343 cm/us, divide by 2 (round trip).
  return (long)(duration * 0.0343 / 2.0);
}
