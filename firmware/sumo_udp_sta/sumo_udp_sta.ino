/**
 * SumoBot ESP32 — UDP Station (minimal)
 *
 * Joins an existing WiFi network and listens for UDP control commands
 * on port 4210. Includes a 300 ms safety watchdog that auto-stops the
 * motors if the controller stops sending packets.
 *
 * This is a minimal reference implementation. For the production
 * firmware (with PWM speed control, ultrasonic, and info reporting),
 * see firmware/sumo_main/.
 *
 * Mode      : WiFi STA + UDP
 * Commands  : maju, mundur, kiri, kanan, stop
 * Hardware  : ESP32 + 2x BTS7960 (IBT_2) + 2x DC gear motors
 * UDP port  : 4210
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
char packetBuffer[32];

// ===== Motor pins (BTS7960) =====
const int motorKananMaju   = 26;  // R RPWM
const int motorKananMundur = 25;  // R LPWM
const int motorKiriMaju    = 27;  // L RPWM
const int motorKiriMundur  = 14;  // L LPWM

// ===== PWM config =====
// Fixed duty cycle. For runtime-adjustable speed see sumo_main.
const int speed = 255;

// ===== Safety watchdog =====
const unsigned long COMMAND_TIMEOUT_MS = 300;
unsigned long lastCommandAt = 0;
bool motorRunning = false;

void setup() {
  Serial.begin(115200);

  pinMode(motorKananMaju, OUTPUT);
  pinMode(motorKananMundur, OUTPUT);
  pinMode(motorKiriMaju, OUTPUT);
  pinMode(motorKiriMundur, OUTPUT);

  stopMotor();

  Serial.println();
  Serial.print("Menghubungkan ke WiFi: ");
  Serial.println(ssid);

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.println("WiFi terhubung!");
  Serial.print("IP ESP32: ");
  Serial.println(WiFi.localIP());
  Serial.print("Port UDP: ");
  Serial.println(UDP_PORT);
  Serial.println("Kirim perintah: maju / mundur / kiri / kanan / stop");

  udp.begin(UDP_PORT);
}

void loop() {
  int packetSize = udp.parsePacket();
  if (packetSize) {
    int len = udp.read(packetBuffer, sizeof(packetBuffer) - 1);
    if (len > 0) {
      packetBuffer[len] = '\0';
      // Trim trailing whitespace/newlines from the client
      while (len > 0 && (packetBuffer[len - 1] == '\n' ||
                         packetBuffer[len - 1] == '\r' ||
                         packetBuffer[len - 1] == ' ')) {
        packetBuffer[--len] = '\0';
      }
      handleCommand(packetBuffer);
      lastCommandAt = millis();
    }
  }

  // Safety watchdog — auto-stop if no command for COMMAND_TIMEOUT_MS
  if (motorRunning && (millis() - lastCommandAt > COMMAND_TIMEOUT_MS)) {
    stopMotor();
  }
}

void handleCommand(const char* cmd) {
  if      (strcmp(cmd, "maju")   == 0) gerakMaju();
  else if (strcmp(cmd, "mundur") == 0) gerakMundur();
  else if (strcmp(cmd, "kiri")   == 0) putarKiri();
  else if (strcmp(cmd, "kanan")  == 0) putarKanan();
  else if (strcmp(cmd, "stop")   == 0) stopMotor();
}

// ===== Motor control =====

void gerakMaju() {
  analogWrite(motorKananMaju, 0);
  analogWrite(motorKananMundur, speed);
  analogWrite(motorKiriMaju, 0);
  analogWrite(motorKiriMundur, speed);
  motorRunning = true;
}

void gerakMundur() {
  analogWrite(motorKananMaju, speed);
  analogWrite(motorKananMundur, 0);
  analogWrite(motorKiriMaju, speed);
  analogWrite(motorKiriMundur, 0);
  motorRunning = true;
}

void putarKanan() {
  analogWrite(motorKananMaju, speed);
  analogWrite(motorKananMundur, 0);
  analogWrite(motorKiriMaju, 0);
  analogWrite(motorKiriMundur, speed);
  motorRunning = true;
}

void putarKiri() {
  analogWrite(motorKananMaju, 0);
  analogWrite(motorKananMundur, speed);
  analogWrite(motorKiriMaju, speed);
  analogWrite(motorKiriMundur, 0);
  motorRunning = true;
}

void stopMotor() {
  analogWrite(motorKananMaju, 0);
  analogWrite(motorKananMundur, 0);
  analogWrite(motorKiriMaju, 0);
  analogWrite(motorKiriMundur, 0);
  motorRunning = false;
}
