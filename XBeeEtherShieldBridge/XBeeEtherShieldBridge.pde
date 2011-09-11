/*
 * Arduino ENC28J60 Ethernet shield/Nanode DHCP client test
 */

// If using a Nanode (www.nanode.eu) instead of Arduino and ENC28J60 EtherShield then
// use this define:
#include "WProgram.h"
#include <EtherShield.h>
#include <NewSoftSerial.h>

#define TX_PIN 2
#define RX_PIN 3

NewSoftSerial DebugSerial(RX_PIN, TX_PIN);

// Please modify the following lines. mac and ip have to be unique
// in your local area network. You can not have the same numbers in
// two devices:
// how did I get the mac addr? Translate the first 3 numbers into ascii is: TUX
static uint8_t mymac[6] = { 
  0x54, 0x55, 0x58, 0x12, 0x34, 0x56 };

static uint8_t myip[4] = { 
  0, 0, 0, 0 };
static uint8_t mynetmask[4] = { 
  0, 0, 0, 0 };

// IP address of the host being queried to contact (IP of the first portion of the URL):
static uint8_t websrvip[4] = { 
  0, 0, 0, 0 };

// Default gateway. The ip address of your DSL router. It can be set to the same as
// websrvip the case where there is no default GW to access the 
// web server (=web server is on the same lan as this host) 
static uint8_t gwip[4] = { 
  0, 0, 0, 0};

static uint8_t dnsip[4] = {   0, 0, 0, 0 };
  
static uint8_t dhcpsvrip[4] = { 
  0, 0, 0, 0 };

#define STATUS_LED 13
#define MYWWWPORT 80
#define BUFFER_SIZE 750
static uint8_t buf[BUFFER_SIZE+1];
#define WEBSERVER_VHOST "notmoodydoor.appspot.com"
// API URL to send request to
#define API_URL "/rfid"
#define AUTH_TOKEN "Authorization: Basic xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
#define MAX_RFID_LENGTH 10
static int rfid_index;
char rfid_buf[MAX_RFID_LENGTH];
char rfidstr[15]; //rfid=AABBCCDD
boolean valid_rfid;

// Programmable delay for flashing LED
uint16_t delayRate = 0;

void print_network( uint8_t *buf );
void print_mac();
void print_ip();
void browserresult_callback(uint8_t statuscode, uint16_t datapos);

enum states {
  INIT_CHIPSET = 0,
  ALLOCATE_IP = 1,
  INIT_NETWORKING = 2,
  INIT_WEBCLIENT_GW = 3,
  WAIT_FOR_ARP = 4,
  LOOKUP_IP = 5,
  WAIT_DNS_LOOKUP = 6,
  WAITING_QUERY = 7,
  SEND_QUERY = 8,
  WAITING_QUERY_REPLY = 9,
  PROCESS_REPLY = 10,
  ERROR = 11,
  INIT_SEND_QUERY = 12,
  INIT_WAITING_QUERY = 13,  
};  

static int state;
volatile boolean post_request_pending;
volatile boolean post_error;
boolean processing_packets;
static int buf_datapos;
EtherShield es = EtherShield();
static int failure;
static int max_failure;
static int failure_state;

void setup() {
  DebugSerial.begin(9600);
  DebugSerial.println("Setup starting");
  Serial.begin(9600);
  pinMode(STATUS_LED, OUTPUT);
  set_status_led(false);
  state = INIT_CHIPSET;
  failure = 0;
  max_failure = 0;
  failure_state = ERROR;
  DebugSerial.println("Setup completed");
}

void loop() {
  int start_state;
  int plen;
  boolean valid_packet;
  if(state >= INIT_NETWORKING) {
    // get next packet that needs to be process
    plen = es.ES_enc28j60PacketReceive(BUFFER_SIZE, buf);
    if(es.ES_packetloop_icmp_tcp(buf, plen) > 0) {
      DebugSerial.println("ICMP packet");
      valid_packet = false;
    }
    
    if(plen == 0) {
      valid_packet = false;
    } else {
      valid_packet = true;
    }
  }

  start_state = state;
  
  switch(state) {
  case INIT_CHIPSET:
    es.ES_enc28j60SpiInit();
    DebugSerial.println("Init ENC28J60");
    es.ES_enc28j60Init(mymac);
    DebugSerial.println("Init done");
    DebugSerial.print( "ENC28J60 version " );
    DebugSerial.println( es.ES_enc28j60Revision(), HEX);
    if( es.ES_enc28j60Revision() <= 0 ) {
      DebugSerial.println( "Failed to access ENC28J60");
      state = ERROR;      
    } else {
      state = ALLOCATE_IP;
    }
    break;

  case ALLOCATE_IP:
    if(es.allocateIPAddress(buf, BUFFER_SIZE, mymac, 80, myip, mynetmask, gwip, dnsip, dhcpsvrip ) > 0 ) {
      print_network();
      print_mac();
      state = INIT_NETWORKING;
    } else {
      DebugSerial.println("Failed to get IP address");
      delay(1000); // retry after delay
    }
    break;

  case INIT_NETWORKING:
    es.ES_init_ip_arp_udp_tcp(mymac, myip, 80);
    state = INIT_WEBCLIENT_GW;
    break;

  case INIT_WEBCLIENT_GW:
    es.ES_client_set_gwip(gwip);
    state = WAIT_FOR_ARP;  
    break;

  case WAIT_FOR_ARP:
    if(!valid_packet)
      break;
    if(!es.ES_client_waiting_gw()) {
      DebugSerial.println("Client GW found");
      state = LOOKUP_IP;
    }
    break;

  case LOOKUP_IP:
    DebugSerial.print("Lookup of ");
    DebugSerial.println(WEBSERVER_VHOST);
    es.ES_dnslkup_request(buf, (uint8_t*)WEBSERVER_VHOST);
    state = WAIT_DNS_LOOKUP;
    break;

  case WAIT_DNS_LOOKUP:
    if(!valid_packet)
      break;
    DebugSerial.println("Check for DNS answer");
    if (es.ES_udp_client_check_for_dns_answer(buf, plen) > 0){
      DebugSerial.println("DNS Lookup results received");
      es.ES_client_set_wwwip(es.ES_dnslkup_getip());
      state = INIT_WAITING_QUERY;
    }
    break;

  case INIT_WAITING_QUERY:
    rfid_index = 0;
    state = WAITING_QUERY;
    break;
    
  case WAITING_QUERY:
    while(Serial.available()) {
      char c = Serial.read();
      if(c == '\n') {
        DebugSerial.println("Query received (new line)!");
        rfid_buf[rfid_index] = '\0';
        state = INIT_SEND_QUERY;
      } else if(c == '\r') {
        // ignore... 
      } else {
        rfid_buf[rfid_index++] = c;
        if(rfid_index == MAX_RFID_LENGTH) {
          DebugSerial.println("RFID length exceeded, resetting pointer");
          state = INIT_WAITING_QUERY;
        }
      }
    }
    break;

  case INIT_SEND_QUERY:
    failure = 0;
    max_failure = 5;
    failure_state = INIT_WAITING_QUERY;
    state = SEND_QUERY;
    break;
    
  case SEND_QUERY:
    strcat(rfidstr, "id=");
    es.ES_urlencode(rfid_buf, &(rfidstr[3]));
    es.ES_client_http_post(PSTR( API_URL ), PSTR(WEBSERVER_VHOST), NULL, NULL, rfidstr, &browserresult_callback);
    post_request_pending = true;
    state = WAITING_QUERY_REPLY;
    break;

  case WAITING_QUERY_REPLY:
    if(!post_request_pending) {
      if(!post_error) {
        DebugSerial.println("Valid reply received");
        state = PROCESS_REPLY;
      } else {
        DebugSerial.println("HTTP POST failed");
        failure++;
        state = SEND_QUERY; // retry
      }
    }
    break;

  case PROCESS_REPLY:
    if(valid_rfid) {
      Serial.println("OK");
    } else {
      Serial.println("REJECTED");
    }    
    state = INIT_WAITING_QUERY;
    break;

  case ERROR:
    set_status_led(true);
    break;     

  default:
    DebugSerial.println("ERROR: unsupported state");
    set_status_led(true);    
    break;
  }    
  
  if(max_failure != 0 && failure >= max_failure) {
    state = failure_state;
    max_failure = 0;
    DebugSerial.println("Max failure reached, going to error state");
  }
  
  if(start_state != state) {
    DebugSerial.print("Transition from ");
    DebugSerial.print(start_state);
    DebugSerial.print(" to ");
    DebugSerial.println(state);
  }
}

// Output a ip address from buffer
void print_ip( uint8_t *buf ) {
  for( int i = 0; i < 4; i++ ) {
    DebugSerial.print( buf[i], DEC );
    if( i<3 )
      DebugSerial.print( "." );
  }
}

void browserresult_callback(uint8_t statuscode, uint16_t datapos){
  post_request_pending = false;
  if (statuscode == 0){
    post_error = false;
    DebugSerial.println("POST OK");
    int nl = 0;
    while(nl != 2 && datapos < BUFFER_SIZE) {
      if(buf[datapos] == '\n') {
        nl++;
      } else if(buf[datapos] != '\r') {
        nl = 0;  
      }
      datapos++;
    }
    if(datapos == BUFFER_SIZE) {
      DebugSerial.println("BUFFER OVERFLOW");
    } else {
      valid_rfid = strncmp((char*) &buf[datapos], "OK", 2) == 0;
    }
  } 
  else {
    post_error = true;
    valid_rfid = false;
    DebugSerial.print("POST error returned: ");
    DebugSerial.println(statuscode);
  }
}

void print_mac()
{
  for( int i=0; i<6; i++ ) {
    DebugSerial.print( mymac[i], HEX );
    DebugSerial.print( i < 5 ? ":" : "" );
  }
  DebugSerial.println();

}

void print_network() 
{
    // Display the results:
    DebugSerial.print( "My IP: " );
    print_ip( myip );
    DebugSerial.println();

    DebugSerial.print( "Netmask: " );
    print_ip( mynetmask );
    DebugSerial.println();

    DebugSerial.print( "DNS IP: " );
    print_ip( dnsip );
    DebugSerial.println();

    DebugSerial.print( "GW IP: " );
    print_ip( gwip );
    DebugSerial.println();  
}

void set_status_led(boolean state) 
{
  digitalWrite(STATUS_LED, state?HIGH:LOW);
}
