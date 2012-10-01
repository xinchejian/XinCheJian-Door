/* 

	uses the core13 library for arduino and attiny13 

	this takes an inverted high pulse and turns it into our 
	  unlock/lock to control a 910mhz door control 

	Also added in code to remove door-fucking-action: 
	  we expect a 2000ms inverted HIGH signal and designed 
	  around the major timing flaw with the tiny13 library of 1:1.55

	This is a functional hack, and wireless, braodcasts up to 200m

	1 tplink 703n (90rmb)
	2 npn tranistor 
	2 100Ω resistor

 	1 signal cloner (15rmb) - runs at 5v - even though it should be 12v :) 

	1 attiny13 - (10rmb) - recycle! 
   	  - resiliant, this thing was also powered the wrong way and still works!

*/

unsigned int openpin = PB2; 
unsigned int closepin =PB1;
unsigned int inputpin = PB0; 

void setup() {
  // put your setup code here, to run once:
  pinMode(inputpin, INPUT ); 
  pinMode(closepin, OUTPUT); 
  pinMode(openpin , OUTPUT);
  delay(4000);
}

unsigned long pl(int pin){
  while(digitalRead(pin) == HIGH);
  unsigned long ts = millis();
  while(digitalRead(pin) == LOW);
  return millis() - ts;
}

void loop() {
  unsigned long duration;
  duration = pl(inputpin);
  if (duration > 1862 && duration < 3603) {
    digitalWrite(openpin, HIGH);
    delay(1000);
    digitalWrite(openpin, LOW);
    delay(9000);
    digitalWrite(closepin, HIGH);
    delay(1000);
    digitalWrite(closepin, LOW);
  }
}
