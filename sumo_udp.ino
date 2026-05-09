  #include <WiFi.h>
  #include <WiFiUdp.h>

  // GANTI DENGAN NAMA DAN PASSWORD WIFI DI TEMPAT ANDA
  const char* ssid = "MULYAWAN";
  const char* password = "Bludru50";

  // Port UDP — HP harus kirim perintah ke port ini
  const uint16_t UDP_PORT = 4210;

  WiFiUDP udp;
  char packetBuffer[32];

  // Pin ESP32 untuk IBT_2 Kanan
  const int motorKananMaju = 26;
  const int motorKananMundur = 25;

  // Pin ESP32 untuk IBT_2 Kiri
  const int motorKiriMaju = 27;
  const int motorKiriMundur = 14;

  // Kecepatan Motor (0 - 255)
  int speed = 255;

  // Safety: auto-stop kalau tidak ada perintah masuk dalam X ms
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

    Serial.println("");
    Serial.println("✅ WiFi Terhubung!");
    Serial.print("🌐 IP ESP32: ");
    Serial.println(WiFi.localIP());
    Serial.print("📡 Port UDP: ");
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
        // Buang whitespace trailing (newline dari beberapa client)
        while (len > 0 && (packetBuffer[len - 1] == '\n' ||
                          packetBuffer[len - 1] == '\r' ||
                          packetBuffer[len - 1] == ' ')) {
          packetBuffer[--len] = '\0';
        }
        handleCommand(packetBuffer);
        lastCommandAt = millis();
      }
    }

    // Safety watchdog — kalau HP hilang sinyal, bot berhenti sendiri
    if (motorRunning && (millis() - lastCommandAt > COMMAND_TIMEOUT_MS)) {
      stopMotor();
    }
  }

  void handleCommand(const char* cmd) {
    if (strcmp(cmd, "maju") == 0)        gerakMaju();
    else if (strcmp(cmd, "mundur") == 0) gerakMundur();
    else if (strcmp(cmd, "kiri") == 0)   putarKiri();
    else if (strcmp(cmd, "kanan") == 0)  putarKanan();
    else if (strcmp(cmd, "stop") == 0)   stopMotor();
  }

  // === FUNGSI KONTROL MOTOR ===

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
