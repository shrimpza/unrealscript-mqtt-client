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

event Timer() {
	local byte buf[255];
	local byte next;
	local int read;

	log("IsConnected: " $ IsConnected());

	if (IsDataPending()) {
		in.compact();
		do {
			read = ReadBinary(Min(in.remaining(), 255), buf);
			log("read = " $ read);
			if (read > 0) in.putBytes(buf, 0, read);
		} until (read == 0 || !in.hasRemaining())
		in.flip();
	}

	if (in.hasRemaining()) {
		next = in.get();
		if (((1 << 5) & next) > 0) { // CONNACK message
			connectAck(in);
		} else if (((1 << 4) & next) > 0 && ((1 << 7) & next) > 0) { // SUBACK message
			subscribeAck(in);
		} else if (((1 << 4) & next) > 0 && ((1 << 5) & next) > 0) { // PUBLISH message
			published(in);
		} else if (((1 << 6) & next) > 0) { // PUBACK message
			publishAck(in);
		}
	}
}

function connectAck(ByteBuffer buf) {
	warn("Received connection ack when not in connecting state!");
}

function subscribe(String topic) {
	warn("Cannot subscribe, not connected.");
}

function subscribeAck(ByteBuffer buf) {
	warn("Received subscription ack when not in connected state!");
}

function publish(String topic, String message) {
	warn("Cannot publish, not connected.");
}

function publishAck(ByteBuffer buf) {
	warn("Received publish ack when not in connected state!");
}

function published(ByteBuffer buf) {
	warn("Received published when not in connected state!");
}

event Opened() {
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

event Closed() {
	log("Connection closed!");
}

state Connecting {

	function BeginState() {
		local int was;

		log("In Connecting state");

		out.compact();

		//
		// packet header
		out.put((1 << 4)); // connect message identifier
		out.mark(); // remember position, we need to return here to set the length
		out.put(0); // the length will go here after we construct the body

		//
		// connect header
		out.putString("MQTT"); // protocol header
		out.put(5); // protocol version, 5.0
		out.put(connectFlags(false, false, false, false, false, true)); // connect flags
		out.putShort(60); // keep-alive interval seconds

		//
		// properties - FIXME could be an additional buffer, but just pre-calculating the size now since this is simplistic
		out.putVarInt(5);
		// max packet size property
		out.put(39);
		out.putInt(512); // max packet to 512

		//
		// payload
		out.putString(clientIdent); // client identifier

		//
		// set length and send
		was = out.getPosition();
		out.reset(); // return to mark
		out.putVarInt(was - out.getPosition() - 1);
		out.setPosition(was);
		out.flip();

		sendBuffer(out);
	}

	function connectAck(ByteBuffer buf) {
		local int len, propsLen;
		local byte flags, reasonCode, prop;

		len = buf.getVarInt();
		len += buf.getPosition();
		flags = buf.get();;
		reasonCode = buf.get();
		propsLen = buf.getVarInt();
		propsLen += buf.getPosition();
		while (buf.getPosition() < propsLen) {
		  prop = buf.get();
			switch (prop) {
				case 0x11: // session expiry interval
				  // 4 byte int
				  log("session expiry interval: " $ buf.getInt());
				  break;
				case 0x21: // receive maximum
				  // 2 byte short
				  log("receive maximum: " $ buf.getShort());
				  break;
				case 0x24: // maximum qos
				  // 1 byte
				  log("maximum qos: " $ buf.get());
				  break;
				case 0x25: // retain available
				  // 1 byte
				  log("retain available: " $ buf.get());
				  break;
				case 0x27: // maximum packet size
				  // 2 byte short
				  log("maximum packet size: " $ buf.getShort());
				  break;
				case 0x18: // assigned client identifier
				  // variable length string
				  log("client id: " $ buf.getString());
				  break;
				case 0x22: // topic alias maximum
				  // 2 byte short
				  log("topic alias maximum: " $ buf.getShort());
				  break;
				case 0x1f: // reason string
					log("reason string: " $ buf.getString());
				  break;
				case 0x26: // user properties, repeats
					log("user property name : " $ buf.getString());
					log("user property value: " $ buf.getString());
				  break;
				case 0x28: // wildcard subscription available
				  // 1 byte
				  log("wildcard subscription available: " $ buf.get());
				  break;
				case 0x29: // subscription identifiers available
				  // 1 byte
				  log("subscription identifiers available: " $ buf.get());
				  break;
				case 0x2a: // shared subscriptions available
				  // 1 byte
				  log("shared subscriptions available: " $ buf.get());
				  break;
				case 0x13: // server keep alive
				  // 2 byte short
				  log("server keep alive: " $ buf.getShort());
				  break;
				case 0x1a: // response information
				  log("response information: " $ buf.getString());
				  break;
				case 0x1a: // server reference
				  log("response information: " $ buf.getString());
				  break;
				case 0x15: // authentication method
				  log("auth method: " $ buf.getString());
				  break;
				case 0x16: // auth data
				  // ... byte binary data... everything until end of properties?
				  buf.setPosition(propsLen);
				  break;
				default:
					warn("received unknown property identifier: " $ prop);
					return;
			}
		}

		GotoState('Connected');
	}
}

state Connected {

	function subscribeAck(ByteBuffer buf) {
		local byte reasonCode, prop;
		local int len, propsLen, ident;

		log("Subscribed!");

		len = buf.getVarInt();
		len += buf.getPosition();
		ident = buf.getShort();
		if (ident != packetIdent) warn("Received packet ident " $ ident $ " but was expecting " $ packetIdent);
		propsLen = buf.getVarInt();
		propsLen += buf.getPosition();
		while (buf.getPosition() < propsLen) {
			prop = buf.get();
			switch (prop) {
				case 0x26: // user properties, repeats
					log("user property name : " $ buf.getString());
					log("user property value: " $ buf.getString());
					break;
				default:
					warn("received unknown property identifier: " $ prop);
					return;
			}
		}

		while (buf.getPosition() < len) {
			reasonCode = buf.get();
			log("reason code: " $ reasonCode);
		}
	}

	function subscribe(String topic) {
		local int was;

		log("Subscribing to topic " $ topic);

		out.compact();

		//
		// packet header
		out.put((1 << 7) | (1 << 1)); // subscribe message identifier
		out.mark(); // remember position, we need to return here to set the length
		out.put(0); // the length will go here after we construct the body

		//
		// subscription header
		out.putShort(++packetIdent); // packet identifier - ack should match this
		out.put(0); // properties length - 0, none

		//
		// subscriptions
		out.putString(topic); // subscription name
		out.put(0); // subscription options - 0, none

		//
		// set length and send
		was = out.getPosition();
		out.reset(); // return to mark
		out.putVarInt(was - out.getPosition() - 1);
		out.setPosition(was);
		out.flip();

		sendBuffer(out);
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
