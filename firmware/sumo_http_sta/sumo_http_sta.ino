/**
 * SumoBot ESP32 — HTTP Station (browser controller)
 *
 * Joins an existing WiFi network and serves a touch-friendly D-Pad
 * web UI on port 80. No mobile app needed — open the ESP32's IP in
 * any phone browser to drive the bot.
 *
 * Mode      : WiFi STA + HTTP web UI
 * Endpoints : GET / (UI), /maju, /mundur, /kiri, /kanan, /stop
 * Hardware  : ESP32 + 2x BTS7960 (IBT_2) + 2x DC gear motors
 *
 * Tim Kelompok:
 *   1. Anak Agung Gde Weida Ksatriawarma     (230010002)
 *   2. Vincent Alfian Artha                  (230010009)
 *   3. ANAK AGUNG NGURAH BAJRA DIPA NAROTAMA (230010037)
 *   4. I Kadek Danda Permana                 (230010066)
 *   5. Joshua Caleb Abril                    (230010041)
 */

#include <WiFi.h>
#include <WebServer.h>

// ===== WiFi =====
const char* ssid     = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";

// ===== Web server =====
WebServer server(80);

// ===== Motor pins (BTS7960) =====
const int motorKananMaju   = 26;  // R RPWM
const int motorKananMundur = 25;  // R LPWM
const int motorKiriMaju    = 27;  // L RPWM
const int motorKiriMundur  = 14;  // L LPWM

// ===== PWM config =====
const int speed = 255;  // 0-255

// HTML/CSS/JS for the on-phone D-Pad controller
const char* htmlPage = R"rawliteral(
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <title>Sumobot Control</title>
  <style>
    body {
      font-family: sans-serif; text-align: center; background-color: #1a1a1a;
      color: white; margin: 0; padding-top: 50px; user-select: none; touch-action: manipulation;
    }
    h1 { font-size: 26px; margin-bottom: 40px; }
    .dpad {
      display: grid; grid-template-columns: repeat(3, 85px); grid-template-rows: repeat(3, 85px);
      gap: 15px; justify-content: center;
    }
    .btn {
      background-color: #4CAF50; border: none; border-radius: 50%; color: white;
      font-size: 40px; display: flex; align-items: center; justify-content: center;
      box-shadow: 0 8px #2E7D32; outline: none;
    }
    .btn:active { background-color: #45a049; box-shadow: 0 3px #2E7D32; transform: translateY(5px); }
    .stop { background-color: #f44336; box-shadow: 0 8px #d32f2f; }
    .stop:active { background-color: #e53935; box-shadow: 0 3px #d32f2f; }
    .empty { visibility: hidden; }
  </style>
</head>
<body>
  <h1>Sumobot Controller</h1>
  <div class="dpad">
    <div class="empty"></div>
    <button class="btn" ontouchstart="send('maju')" ontouchend="send('stop')" onmousedown="send('maju')" onmouseup="send('stop')">^</button>
    <div class="empty"></div>

    <button class="btn" ontouchstart="send('kiri')" ontouchend="send('stop')" onmousedown="send('kiri')" onmouseup="send('stop')"><</button>
    <button class="btn stop" onclick="send('stop')">STOP</button>
    <button class="btn" ontouchstart="send('kanan')" ontouchend="send('stop')" onmousedown="send('kanan')" onmouseup="send('stop')">></button>

    <div class="empty"></div>
    <button class="btn" ontouchstart="send('mundur')" ontouchend="send('stop')" onmousedown="send('mundur')" onmouseup="send('stop')">v</button>
    <div class="empty"></div>
  </div>

  <script>
    function send(cmd) { fetch("/" + cmd); }
    window.oncontextmenu = function(event) { event.preventDefault(); event.stopPropagation(); return false; };
  </script>
</body>
</html>
)rawliteral";

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
  Serial.print("Buka browser HP, ketik IP berikut: ");
  Serial.println(WiFi.localIP());

  server.on("/",       []() { server.send(200, "text/html",  htmlPage); });
  server.on("/maju",   []() { gerakMaju();   server.send(200, "text/plain", "Maju"); });
  server.on("/mundur", []() { gerakMundur(); server.send(200, "text/plain", "Mundur"); });
  server.on("/kiri",   []() { putarKiri();   server.send(200, "text/plain", "Kiri"); });
  server.on("/kanan",  []() { putarKanan();  server.send(200, "text/plain", "Kanan"); });
  server.on("/stop",   []() { stopMotor();   server.send(200, "text/plain", "Stop"); });

  server.begin();
}

void loop() {
  server.handleClient();
}

// ===== Motor control =====

void gerakMaju() {
  analogWrite(motorKananMaju, 0);
  analogWrite(motorKananMundur, speed);
  analogWrite(motorKiriMaju, 0);
  analogWrite(motorKiriMundur, speed);
}

void gerakMundur() {
  analogWrite(motorKananMaju, speed);
  analogWrite(motorKananMundur, 0);
  analogWrite(motorKiriMaju, speed);
  analogWrite(motorKiriMundur, 0);
}

void putarKanan() {
  analogWrite(motorKananMaju, speed);
  analogWrite(motorKananMundur, 0);
  analogWrite(motorKiriMaju, 0);
  analogWrite(motorKiriMundur, speed);
}

void putarKiri() {
  analogWrite(motorKananMaju, 0);
  analogWrite(motorKananMundur, speed);
  analogWrite(motorKiriMaju, speed);
  analogWrite(motorKiriMundur, 0);
}

void stopMotor() {
  analogWrite(motorKananMaju, 0);
  analogWrite(motorKananMundur, 0);
  analogWrite(motorKiriMaju, 0);
  analogWrite(motorKiriMundur, 0);
}
