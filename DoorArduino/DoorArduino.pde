#include <NewSoftSerial.h>

#define TX_PIN_DEBUG 4 // white, rx, 
#define RX_PIN_DEBUG 5 // tx

NewSoftSerial DebugSerial(RX_PIN_DEBUG, TX_PIN_DEBUG);

#define TX_PIN 2
#define RX_PIN 3
#define MAX_RFID_LENGTH 10
char rfid_buf[MAX_RFID_LENGTH];
char rfidstr[15]; //rfid=AABBCCDD
static int rfid_index;
int RFIDVal = 0;
int status = 0;
unsigned char searchCMD[] = {
  0xAA, 0xBB, 0x02, 0x20, 0x22 };
unsigned char searchRES[5] = {
  0x0, 0x0, 0x0, 0x0, 0x0 };
NewSoftSerial rfid_serial(RX_PIN, TX_PIN);
unsigned long lastValidRfidTimeMillis;
int motorB_pins[] = { 
  11, 8, 9 }; // motor B
int motorA_pins[] = { 
  13, 12, 10 }; // motor A
int* lock_motor = motorA_pins;
long start_movement;

enum {
  DIR1,
  DIR2,
  SPEED
};


boolean searchCard()
{
  for(int i=0; i<5; i++) { 
    rfid_serial.print((char)searchCMD[i]);
  }

  status = 0;
  boolean new_result = false;
  if(lastValidRfidTimeMillis != 0 && ((millis() - lastValidRfidTimeMillis) > 5000)) {
    DebugSerial.println("Expired RFID debouncer");
    for(int i=0; i<4; i++) {
      searchRES[i] = 0x0; 
    }
    lastValidRfidTimeMillis = 0;
  }
  while(!rfid_serial.available());
  // listen for new serial coming in
  while(rfid_serial.available()) {
    RFIDVal = rfid_serial.read();
    if (RFIDVal != 0) {
      // when a Tag has been detected, the string returned by the RFID reader has a header string that is: 0xAA 0xBB 0x06 0x20
      // which is a bit different from the searchCMD values
      switch (status) {
      case 0:  // parse 0xAA
        if (RFIDVal == 0xAA) status = 1;
        break;
      case 1: // parse 0xBB
        if (RFIDVal == 0xBB) status = 2;
        else return false;
        break;
      case 2: // parse 0x06
        if (RFIDVal == 0x06) status = 3;
        else return false;
        break;
      case 3: // parse 0x20
        if (RFIDVal == 0x20) status = 4;
        else return false;
        break;
      case 4:
      case 5:
      case 6:
      case 7:
        if(searchRES[status - 4] != RFIDVal) {
          lastValidRfidTimeMillis = millis();
          new_result = true;
          searchRES[status - 4] = RFIDVal;
        }
        status ++;
        break;
      case 8:
        return new_result; // read successfully but might be a repeat
        break;
      default:
        return false;
        break;
      }
    }
  }
  return false;
}

void move_motor(int pins[], int dir)
{
  digitalWrite(pins[DIR1], LOW);
  digitalWrite(pins[DIR2], LOW);
  analogWrite(pins[SPEED], 255);
  // set direction
  if (dir == -1) {
    Serial.println("Direction = -1");
    digitalWrite(pins[DIR1], LOW);
    digitalWrite(pins[DIR2], HIGH);
  } 
  else if(dir == 0) {
    Serial.println("Direction = 0");
    digitalWrite(pins[DIR1], LOW);
    digitalWrite(pins[DIR2], LOW);
  } 
  else if(dir == 1) {
    Serial.println("Direction = 1");
    digitalWrite(pins[DIR1], HIGH);
    digitalWrite(pins[DIR2], LOW);  
  }
}

void lock_door()
{
  move_motor(lock_motor, -1);
  start_movement = millis();
}

void unlock_door()
{
  move_motor(lock_motor, 1);
  start_movement = millis();
}

boolean lock_state = true;

void setup()
{
  rfid_serial.begin(19200);
  for(int i=0; i<3; i++)
    pinMode(lock_motor[i], OUTPUT);
  DebugSerial.begin(9600);
  Serial.begin(9600);
  DebugSerial.println("Setup completed");
}

char response[50];

void print_rfid(unsigned char* rfid) {
  for(int i=0; i<4; i++) 
    Serial.print(rfid[i], HEX);
  Serial.println();
}

void loop()
{
  int i;
  if(start_movement != 0 && (millis() - start_movement > 2000)) {
      move_motor(lock_motor, 0);
      start_movement = 0;
  }
  if(searchCard()) {
    print_rfid(searchRES);
    i = 0;
    char c = 0;
    DebugSerial.println("looking up RFID");
    long start_time = millis();
    
    while(c != '\r' && c != '\n') {
        if(Serial.available()) {
          c = Serial.read();
          response[i++] = c;
          DebugSerial.print(c, HEX);
        }  else {
          DebugSerial.print(i, DEC);
          delay(100);
        }
        if(millis() - start_time > 5000) {
          break;
        } 
    } 
    /*delay(2000);
    while(Serial.available()) {
      char c = Serial.read();
      if(c == '\n') {
        DebugSerial.println("Query received (new line)!");
        response[rfid_index] = '\0';
      } else if(c == '\r') {
        // ignore... 
      } else {
        response[i] = c;
      }
      if(millis() - start_time > 5000) {
        break;
      } 
    }*/
    
    response[i] = '\0';
    DebugSerial.println(response);
    if(strncmp(response, "OK", 2) == 0) {
      DebugSerial.println("Accepted");
      if(lock_state) {
        unlock_door();
        lock_state = false;  
      } 
      else {
        lock_door();
        lock_state = true;
      }
    } else if(strncmp(response, "REJECTED", 8) == 0) {
      DebugSerial.println("Rejected");
    } else {
      // ignore
    }
  } 
}


