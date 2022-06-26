class MQTTClient extends TCPLink;

// connection properties
var String mqttHost;
var int mqttPort;

// state
var private int packetIdent;

static final operator(18) int % (int A, int B) {
  return A - (A / B) * B;
}

function PostBeginPlay() {
	local IpAddr ip;

	packetIdent = 0;

	// these need to be set at runtime
  LinkMode = MODE_Binary;
  ReceiveMode = RMODE_Manual;

	if (StringToIpAddr(mqttHost, ip)) {
		ip.port = mqttPort;
		log("Got IP for host " $ mqttHost $ " = " $ ip.Addr);
	} else {
		warn("Failed to get IP for host " $ mqttHost);
		return;
	}

	if(BindPort() == 0) {
		warn("Error binding local port.");
		return;
	}

	if (Open(ip)) {
		log("Connected!");
		SetTimer(1, True);
	} else {
		warn("Connection failed!");
	}
}

event Opened() {
	local byte B[255];
	local int encLen, i, cur;

	log("Connection opened!");

	// send CONNECT
	cur = 0;
	B[cur++] = 0 | (1 << 4); // connect message identifier
	B[cur++] = 0; // length will be set
	setProtoHeader(B, cur);
	setConnectFlags(false, false, false, false, false, true, B, cur);
	writeShort(60, B, cur); // timeout
	writeVarInt(5, B, cur); // size of properties FIXME size

	B[cur++] = 39; // max packet size property
	writeInt(255, B, cur); // max packet to 255
  writeString("helloworld", B, cur);

  // set the length at byte 2... FIXME
  i = 1;
  writeVarInt(cur - 2, B, i);

	SendBinary(cur, B);
	GotoState('Connecting');
}

function writeShort(int val, out byte dst[255], out int pos) {
	dst[pos++] = ((val >> 8) & 0xff);
	dst[pos++] = val & 0xff;
}

function int readShort(byte src[255], out int pos) {
  return src[pos++] << 8 | src[pos++];
}

function writeInt(int val, out byte dst[255], out int pos) {
	dst[pos++] = (val & 0xff000000) >> 24;
	dst[pos++] = (val & 0x00ff0000) >> 16;
	dst[pos++] = (val & 0x0000ff00) >> 8;
	dst[pos++] =  val & 0x000000ff;
}

function setProtoHeader(out byte dst[255], out int pos) {
	writeString("MQTT", dst, pos);
	dst[pos++] = 5; // mqtt version 5.0
}

function setConnectFlags(bool hasUserName, bool hasPassword, bool willRetain, bool wilQos, bool willFlag, bool cleanStart, out byte dst[255], out int pos) {
	if (hasUserName) 	dst[pos] = dst[pos] | (1 << 7);
	if (hasPassword) 	dst[pos] = dst[pos] | (1 << 6);
	if (willRetain) 	dst[pos] = dst[pos] | (1 << 5);
	if (wilQos) 			dst[pos] = dst[pos] | (1 << 4);
	if (wilQos) 			dst[pos] = dst[pos] | (1 << 3);
	if (willFlag) 		dst[pos] = dst[pos] | (1 << 2);
	if (cleanStart) 	dst[pos] = dst[pos] | (1 << 1);
	// final bit reserved

	pos++;
}

function arrayCopy(byte src[255], int len, out byte dst[255], int pos) {
	local int i;
	for (i = 0; i < len; i++) {
		dst[i + pos] = src[i];
	}
}

function int writeString(String str, out byte dst[255], out int pos) {
	local int i;

	writeShort(Len(str), dst, pos);
	for (i = 0; i < Len(str); i++) {
		dst[pos++] = Asc(Mid(str, i, 1));
	}

	return i;
}

function String readString(byte src[255], out int pos) {
	local int len, i;
	local String str;

	len = readShort(src, pos);

	for (i = 0; i < len; i++) {
		str = str $ Chr(src[pos++]);
	}

	return str;
}

event Closed() {
	log("Connection closed!");
}

event Timer() {
	// nothing, implemented within states
}

function writeVarInt(int value, out byte dst[255], out int pos) {
  local byte encodedByte, rem, len;

	if (value > 268435455) {
		warn("Cannot encode size larger than 268435455, got " $ value);
		return;
	}

  rem = value;
	do {
		encodedByte = rem % 128;
		rem = rem / 128;
		if (rem > 0) encodedByte = encodedByte | 128;
		dst[pos++] = encodedByte;
	} until (!(rem > 0))
}

function int readVarInt(byte buf[255], out int pos) {
  local int multiplier, value;
  local byte encodedByte;

  multiplier = 1;
  value = 0;

  do {
		encodedByte = buf[pos++];
		value += (encodedByte & 127) * multiplier;
		if (multiplier > 128*128*128) {
			warn("Malformed Variable Byte value at position " $ pos);
			return -1;
		}
		multiplier *= 128;
 	} until (!((encodedByte & 128) != 0))

 	return value;
}

/**
 * Reads a variable length value directly off the incoming socket data.
 */
function int readVarIntDirectly() {
	local byte buf[255];
  local int multiplier, value;
  local byte encodedByte;

  multiplier = 1;
  value = 0;

  do {
  	ReadBinary(1, buf);
		encodedByte = buf[0];
		value += (encodedByte & 127) * multiplier;
		if (multiplier > 128*128*128) {
			warn("Malformed Variable Byte value");
			return -1;
		}
		multiplier *= 128;
 	} until (!((encodedByte & 128) != 0))

 	return value;
}

state Connecting {

	function BeginState() {
		log("In Connecting state");
	}

	event Timer() {
		local byte buf[255];
  	local int read, i, b;
  	local bool isConnectAck;

  	log("IsConnected: " $ IsConnected());

  	if (IsDataPending()) {
  		read = ReadBinary(255, buf);
  		log("read = " $ read);
  		if (read > 0) {
  			if (((1 << 5) & buf[0]) > 0) { // CONNACK message
  				connectAck();
  			} else {
  				warn("Unknown message type received when expecting CONNACK");
  			}
  		}
  	}
	}

	function connectAck() {
		local int len, cur;
		local byte buf[255];
		local byte flags, reasonCode, prop;

		len = readVarIntDirectly();
		log("payload length: " $ len);
		log("DataPending: " $ DataPending);
		ReadBinary(len, buf);
		cur = 0;
		flags = buf[cur++];
		reasonCode = buf[cur++];
		log("reasonCode: " $ reasonCode);
		len = readVarInt(buf, cur);
		log("props len: " $ len);
		len += cur;
		while (cur < len) {
		  prop = buf[cur++];
		  log("reading property: " $ prop);
			switch (prop) {
				case 0x11: // session expiry interval
				  // 4 byte int
				  cur += 4;
				  break;
				case 0x21: // receive maximum
				  // 2 byte short
				  log("receive maximum: " $ readShort(buf, cur));
				  break;
				case 0x24: // maximum qos
				  // 1 byte
				  cur ++;
				  break;
				case 0x25: // retain available
				  // 1 byte
				  cur ++;
				  break;
				case 0x27: // maximum packet size
				  // 2 byte short
				  cur += 2;
				  break;
				case 0x18: // assigned client identifier
				  // variable length string
					log("client id: " $ readString(buf, cur));
				  break;
				case 0x22: // topic alias maximum
				  // 2 byte short
				  log("topic alias maximum: " $ readShort(buf, cur));
				  break;
				case 0x1f: // reason string
					log("reason string: " $ readString(buf, cur));
				  break;
				case 0x26: // user properties, repeats
					log("user property name : " $ readString(buf, cur));
					log("user property value: " $ readString(buf, cur));
				  break;
				case 0x28: // wildcard subscription available
				  // 1 byte
				  cur ++;
				  break;
				case 0x29: // subscription identifiers available
				  // 1 byte
				  cur ++;
				  break;
				case 0x2a: // shared subscriptions available
				  // 1 byte
				  cur ++;
				  break;
				case 0x13: // server keep alive
				  // 2 byte short
				  cur += 2;
				  break;
				case 0x1a: // response information
				  log("response information: " $ readString(buf, cur));
				  break;
				case 0x1a: // server reference
				  log("response information: " $ readString(buf, cur));
				  break;
				case 0x15: // authentication method
				  log("auth method: " $ readString(buf, cur));
				  break;
				case 0x16: // auth data
				  // ... byte binary data... everything until end of properties?
				  cur = len;
				  break;
				default:
					warn("received unknown property identifier: " $ buf[cur-1]);
					return;
			}
		}

		GotoState('Connected');
	}
}

state Connected {

	event Timer() {
		local byte buf[255];
  	local int read, i, b;
  	local bool isConnectAck;

  	log("IsConnected: " $ IsConnected());

  	if (IsDataPending()) {
  		read = ReadBinary(1, buf);
  		log("read = " $ read);
  		if (read > 0) {
  			if (((1 << 4) & buf[0]) > 0
  					&& ((1 << 7) & buf[0]) > 0) { // SUBACK message
//  			if (buf[0] == 0x90) { // SUBACK message
  				subscribeAck();
  			} else {
  				warn("Unknown message type received when expecting SUBACK: " $ buf[0]);
  			}
  		}
  	}
	}

	function subscribeAck() {
		local byte reasonCode, prop;
		local int len, propsLen, cur;
		local byte buf[255];

		log("Subscribed!");

		len = readVarIntDirectly();
		ReadBinary(len, buf);
		log("packet ident: " $ readShort(buf, cur));
		propsLen = readVarInt(buf, cur);
		log("props len: " $ propsLen);
		propsLen += cur;
		while (cur < propsLen) {
			prop = buf[cur++];
			log("reading property: " $ prop);
			switch (prop) {
				case 0x26: // user properties, repeats
					log("user property name : " $ readString(buf, cur));
					log("user property value: " $ readString(buf, cur));
					break;
				default:
					warn("received unknown property identifier: " $ buf[cur-1]);
					return;
			}
		}

		log("cur: " $ cur $ " len: " $ len);

		while (cur < len) {
			reasonCode = buf[cur++];
			log("reason code: " $ reasonCode);
		}
	}

	function subscribe(String topic) {
		local byte B[255];
		local int encLen, i, cur;

		log("Subscribing to topic " $ topic);

		// send CONNECT
		cur = 0;
		//
		B[cur] = 0 | (1 << 7); // connect message identifier
		B[cur] = B[cur] | (1 << 1); // connect message identifier
		cur++;
//		B[cur++] = 0x82; // subscribe message identifier
		B[cur++] = 0; // length will be set
		// subscription header
		//
		writeShort(++packetIdent, B, cur); // packet identifier - ack should match this
		B[cur++] = 0; // properties length - 0, none

		// subscriptions
		writeString("lol", B, cur); // subscription name
		B[cur++] = 0; // subscription options - 0, none

		// set the length at byte 2... FIXME
		i = 1;
		writeVarInt(cur - 2, B, i);

		SendBinary(cur, B);
	}

Begin:
	log("In Connected state");
	Subscribe("lol");
}

defaultproperties {
  mqttHost="192.168.2.128"
  mqttPort=1883
}
