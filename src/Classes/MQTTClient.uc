class MQTTClient extends TCPLink;

// connection properties
var String mqttHost;
var int mqttPort;
var String clientIdent;

// state
var private int packetIdent;

var private ByteBuffer out;
var private ByteBuffer in;

static final operator(18) int % (int A, int B) {
  return A - (A / B) * B;
}

function PreBeginPlay() {
	Super.PreBeginPlay();

	out = new class'ByteBuffer';
	in = new class'ByteBuffer';
}

function PostBeginPlay() {
	local IpAddr ip;

	Super.PostBeginPlay();

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

function connectAck() {
	warn("Received connection ack when not in connecting state!");
}

function subscribe(String topic) {
	warn("Cannot subscribe, not connected.");
}

function subscribeAck() {
	warn("Received subscription ack when not in connected state!");
}

function publish(String topic, String message) {
	warn("Cannot publish, not connected.");
}

function publishAck() {
	warn("Received publish ack when not in connected state!");
}

function published() {
	warn("Received published when not in connected state!");
}

event Opened() {
	local int was;

	log("Connection opened!");

	in.clear();
	out.clear();

	GotoState('Connecting');
}

function sendBuffer(ByteBuffer send) {
	local byte b[255];
	local int len;

	while (send.hasRemaining()) {
		len = send.getBytes(b, 255);
		SendBinary(len, b);
	}
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

//function setProtoHeader(out byte dst[255], out int pos) {
//	writeString("MQTT", dst, pos);
//	dst[pos++] = 5; // mqtt version 5.0
//}

function byte connectFlags(bool hasUserName, bool hasPassword, bool willRetain, bool wilQos, bool willFlag, bool cleanStart) {
	local byte b;

	b = 0;
	if (hasUserName) 	b = b | (1 << 7);
	if (hasPassword) 	b = b | (1 << 6);
	if (willRetain) 	b = b | (1 << 5);
	if (wilQos) 			b = b | (1 << 4);
	if (wilQos) 			b = b | (1 << 3);
	if (willFlag) 		b = b | (1 << 2);
	if (cleanStart) 	b = b | (1 << 1);
	// final bit reserved

	return b;
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

//event Timer() {
//	// nothing, implemented within states
//}

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

		// send CONNECT
		out.put((1 << 4)); // connect message identifier
		out.mark(); // remember position, we need to return here to set the length
		out.put(0); // the length will go here after we construct the body
		out.putString("MQTT"); // protocol header
		out.put(5); // protocol version, 5.0
		out.put(connectFlags(false, false, false, false, false, true)); // connect flags
		out.putShort(60); // keep-alive interval seconds

		// properties - FIXME could be an additional buffer, but just pre-calculating the size now since this is simplistic
		out.putVarInt(5);
		// max packet size property
		out.put(39);
		out.putInt(512); // max packet to 512

		out.putString(clientIdent); // client identifier

		// prepare message to send
		was = out.getPosition();
		out.reset(); // return to mark
		out.putVarInt(was - out.getPosition() - 1);
		out.setPosition(was);
		out.flip();

		sendBuffer(out);
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
		B[cur] = (1 << 7) | (1 << 1); // subscribe message identifier
		cur++;
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
	clientIdent="utserver"
  mqttHost="192.168.2.128"
  mqttPort=1883
}
