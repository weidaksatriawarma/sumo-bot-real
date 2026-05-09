#include <WiFi.h>
#include <WiFiUdp.h>

// --- STA Mode: konek ke router rumah ---
const char* ssid     = "Vriox";
const char* password = "BukanSakur@9000";

// Port UDP harus sama dengan app (kEspUdpPort = 4210)
const uint16_t UDP_PORT = 4210;

WiFiUDP udp;

// Pin motor (BTS7960 / H-bridge, RPWM/LPWM per motor)
const int motorKananMaju   = 26;  // R motor RPWM
const int motorKananMundur = 25;  // R motor LPWM
const int motorKiriMaju    = 27;  // L motor RPWM
const int motorKiriMundur  = 14;  // L motor LPWM

// HC-SR04 ultrasonic sensor (jarak depan)
const int ULTRASONIC_TRIG = 5;
const int ULTRASONIC_ECHO = 18;
const unsigned long ULTRASONIC_TIMEOUT_US = 30000UL;  // ~5 m max range

int speed = 200;  // 0-255 — runtime adjustable via "spd:N"

void gerakMaju();
void gerakMundur();
void putarKiri();
void putarKanan();
void stopMotor();
void replyTo(IPAddress ip, uint16_t port, const char* msg);
long readDistanceCm();

void setup() {
  Serial.begin(115200);

  // PWM 20kHz, 8-bit — di atas audio range, motor silent
  ledcAttach(motorKananMaju,   20000, 8);
  ledcAttach(motorKananMundur, 20000, 8);
  ledcAttach(motorKiriMaju,    20000, 8);
  ledcAttach(motorKiriMundur,  20000, 8);
  stopMotor();

  // HC-SR04 ultrasonic
  pinMode(ULTRASONIC_TRIG, OUTPUT);
  pinMode(ULTRASONIC_ECHO, INPUT);
  digitalWrite(ULTRASONIC_TRIG, LOW);

  // STA mode — konek ke WiFi rumah, IP dinamis dari DHCP
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  Serial.println();
  Serial.print("Menghubungkan ke WiFi: "); Serial.println(ssid);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println();
  Serial.println("WiFi terhubung!");
  Serial.print("IP ESP32  : "); Serial.println(WiFi.localIP());
  Serial.print("UDP PORT  : "); Serial.println(UDP_PORT);
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

  // trim trailing whitespace/newline
  while (len > 0 && (buf[len-1] == '\n' || buf[len-1] == '\r' || buf[len-1] == ' ')) {
    buf[--len] = '\0';
  }

  String cmd = String(buf);
  cmd.toLowerCase();

  IPAddress remoteIp = udp.remoteIP();
  uint16_t  remotePort = udp.remotePort();

  if (cmd == "ping") {
    replyTo(remoteIp, remotePort, "pong");
    return;
  }

  // "spd:180" or "pwm:180" — set PWM duty 0-255 (motor speed)
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

  // "info" — report PWM configuration
  if (cmd == "info") {
    char reply[48];
    snprintf(reply, sizeof(reply),
             "info:freq=20000,duty=%d,res=8,max=255", speed);
    replyTo(remoteIp, remotePort, reply);
    return;
  }

  // "dist" — read HC-SR04 ultrasonic, reply "dist:NN" cm (or "dist:-1" if no echo)
  if (cmd == "dist") {
    long d = readDistanceCm();
    char reply[16];
    if (d < 0) strcpy(reply, "dist:-1");
    else snprintf(reply, sizeof(reply), "dist:%ld", d);
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

// --- Motor control ---
void gerakMaju() {
  ledcWrite(motorKananMaju, speed); ledcWrite(motorKananMundur, 0);
  ledcWrite(motorKiriMaju, 0);      ledcWrite(motorKiriMundur, speed);
}
void gerakMundur() {
  ledcWrite(motorKananMaju, 0);     ledcWrite(motorKananMundur, speed);
  ledcWrite(motorKiriMaju, speed);  ledcWrite(motorKiriMundur, 0);
}
void putarKanan() {
  ledcWrite(motorKananMaju, 0); ledcWrite(motorKananMundur, speed);
  ledcWrite(motorKiriMaju, 0);  ledcWrite(motorKiriMundur, speed);
}
void putarKiri() {
  ledcWrite(motorKananMaju, speed); ledcWrite(motorKananMundur, 0);
  ledcWrite(motorKiriMaju, speed);  ledcWrite(motorKiriMundur, 0);
}
void stopMotor() {
  ledcWrite(motorKananMaju, 0); ledcWrite(motorKananMundur, 0);
  ledcWrite(motorKiriMaju, 0);  ledcWrite(motorKiriMundur, 0);
}

// HC-SR04 — return distance in cm, -1 if out of range / no echo
long readDistanceCm() {
  digitalWrite(ULTRASONIC_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(ULTRASONIC_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(ULTRASONIC_TRIG, LOW);

  unsigned long duration = pulseIn(ULTRASONIC_ECHO, HIGH, ULTRASONIC_TIMEOUT_US);
  if (duration == 0) return -1;
  return (long)(duration * 0.0343 / 2.0);
}
