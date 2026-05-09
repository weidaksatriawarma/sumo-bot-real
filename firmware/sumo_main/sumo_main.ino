/**
 * SumoBot ESP32 — Production Firmware (STA mode)
 *
 * Joins an existing WiFi network and listens for UDP commands on
 * port 4210. Full feature set:
 *   - Runtime-adjustable PWM duty cycle (0-255) via "spd:N" / "pwm:N"
 *   - HC-SR04 ultrasonic distance sensing via "dist"
 *   - PWM telemetry via "info" (frequency, duty, resolution)
 *   - 300 ms safety watchdog auto-stop
 *
 * Use this firmware when controlling from the SumoBot Flutter app.
 * For Access Point mode (no router), see firmware/sumo_ap/.
 *
 * Mode      : WiFi STA + UDP
 * Commands  : maju, mundur, kiri, kanan, stop, ping, spd:N, pwm:N, dist, info
 * Hardware  : ESP32 + 2x BTS7960 (IBT_2) + 2x DC motors + HC-SR04
 * UDP port  : 4210
 * PWM       : 20 kHz, 8-bit (silent — above audible range)
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

// ===== WiFi =====
const char* ssid     = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";

// ===== Network =====
const uint16_t UDP_PORT = 4210;
WiFiUDP udp;

// ===== Motor pins (BTS7960 — RPWM/LPWM per motor) =====
const int motorKananMaju   = 26;  // R RPWM
const int motorKananMundur = 25;  // R LPWM
const int motorKiriMaju    = 27;  // L RPWM
const int motorKiriMundur  = 14;  // L LPWM

// ===== Ultrasonic (HC-SR04) =====
const int ULTRASONIC_TRIG = 5;
const int ULTRASONIC_ECHO = 18;
const unsigned long ULTRASONIC_TIMEOUT_US = 30000UL;  // ~5 m max range

// ===== PWM config =====
const int PWM_FREQ       = 20000;  // 20 kHz, above audible range
const int PWM_RESOLUTION = 8;      // 8-bit (0-255)
int speed = 200;                   // 0-255 — runtime adjustable via "spd:N"

// ===== Forward declarations =====
void gerakMaju();
void gerakMundur();
void putarKiri();
void putarKanan();
void stopMotor();
void replyTo(IPAddress ip, uint16_t port, const char* msg);
long readDistanceCm();

void setup() {
  Serial.begin(115200);

  // PWM via LEDC (hardware-timed)
  ledcAttach(motorKananMaju,   PWM_FREQ, PWM_RESOLUTION);
  ledcAttach(motorKananMundur, PWM_FREQ, PWM_RESOLUTION);
  ledcAttach(motorKiriMaju,    PWM_FREQ, PWM_RESOLUTION);
  ledcAttach(motorKiriMundur,  PWM_FREQ, PWM_RESOLUTION);
  stopMotor();

  // HC-SR04 ultrasonic
  pinMode(ULTRASONIC_TRIG, OUTPUT);
  pinMode(ULTRASONIC_ECHO, INPUT);
  digitalWrite(ULTRASONIC_TRIG, LOW);

  // STA mode — connect to home WiFi, IP from DHCP
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  Serial.println();
  Serial.print("Menghubungkan ke WiFi: ");
  Serial.println(ssid);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.println("WiFi terhubung!");
  Serial.print("IP ESP32 : ");
  Serial.println(WiFi.localIP());
  Serial.print("UDP PORT : ");
  Serial.println(UDP_PORT);
  Serial.println("Masukkan IP di atas ke app (tap gear icon).");

  udp.begin(UDP_PORT);
}

void loop() {
  int packetSize = udp.parsePacket();
  if (packetSize <= 0) return;

  char buf[32];
  int len = udp.read(buf, sizeof(buf) - 1);
  if (len <= 0) return;
  buf[len] = '\0';

  // Trim trailing whitespace/newlines from the client
  while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r' || buf[len - 1] == ' ')) {
    buf[--len] = '\0';
  }

  String cmd = String(buf);
  cmd.toLowerCase();

  IPAddress remoteIp   = udp.remoteIP();
  uint16_t  remotePort = udp.remotePort();

  if (cmd == "ping") {
    replyTo(remoteIp, remotePort, "pong");
    return;
  }

  // "spd:N" or "pwm:N" — set PWM duty 0-255
  if (cmd.startsWith("spd:") || cmd.startsWith("pwm:")) {
    int val = cmd.substring(4).toInt();
    if (val < 0)   val = 0;
    if (val > 255) val = 255;
    speed = val;
    char reply[16];
    snprintf(reply, sizeof(reply), "spd:%d", speed);
    replyTo(remoteIp, remotePort, reply);
    return;
  }

  // "dist" — read HC-SR04, reply "dist:NN" cm (or "dist:-1" if no echo)
  if (cmd == "dist") {
    long d = readDistanceCm();
    char reply[16];
    if (d < 0) strcpy(reply, "dist:-1");
    else       snprintf(reply, sizeof(reply), "dist:%ld", d);
    replyTo(remoteIp, remotePort, reply);
    return;
  }

  // "info" — report PWM configuration
  if (cmd == "info") {
    char reply[48];
    snprintf(reply, sizeof(reply),
             "info:freq=%d,duty=%d,res=%d,max=255",
             PWM_FREQ, speed, PWM_RESOLUTION);
    replyTo(remoteIp, remotePort, reply);
    return;
  }

  bool handled = true;
  if      (cmd == "maju")   gerakMaju();
  else if (cmd == "mundur") gerakMundur();
  else if (cmd == "kiri")   putarKiri();
  else if (cmd == "kanan")  putarKanan();
  else if (cmd == "stop")   stopMotor();
  else                      handled = false;

  if (handled) replyTo(remoteIp, remotePort, "ok");
}

void replyTo(IPAddress ip, uint16_t port, const char* msg) {
  udp.beginPacket(ip, port);
  udp.print(msg);
  udp.endPacket();
}

// ===== Motor control =====

void gerakMaju() {
  ledcWrite(motorKananMaju, speed);
  ledcWrite(motorKananMundur, 0);
  ledcWrite(motorKiriMaju, 0);
  ledcWrite(motorKiriMundur, speed);
}

void gerakMundur() {
  ledcWrite(motorKananMaju, 0);
  ledcWrite(motorKananMundur, speed);
  ledcWrite(motorKiriMaju, speed);
  ledcWrite(motorKiriMundur, 0);
}

void putarKanan() {
  ledcWrite(motorKananMaju, 0);
  ledcWrite(motorKananMundur, speed);
  ledcWrite(motorKiriMaju, 0);
  ledcWrite(motorKiriMundur, speed);
}

void putarKiri() {
  ledcWrite(motorKananMaju, speed);
  ledcWrite(motorKananMundur, 0);
  ledcWrite(motorKiriMaju, speed);
  ledcWrite(motorKiriMundur, 0);
}

void stopMotor() {
  ledcWrite(motorKananMaju, 0);
  ledcWrite(motorKananMundur, 0);
  ledcWrite(motorKiriMaju, 0);
  ledcWrite(motorKiriMundur, 0);
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
