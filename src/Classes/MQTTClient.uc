class MQTTClient extends TCPLink;

// connection properties
var String mqttHost;
var int mqttPort;
var int sessionTtl;
var String clientIdent;

// state
var private int packetIdent;
var private int keepAlive; // interval between pings, set to sessionTtl, or overridden by server
var private float pingTime; // RTT for ping requests

var private ByteBuffer out;
var private ByteBuffer in;

static final operator(18) int % (int A, int B) {
  return A - (A / B) * B;
}

function PreBeginPlay() {
	Super.PreBeginPlay();

	// these need to be set at runtime
  LinkMode = MODE_Binary;
  ReceiveMode = RMODE_Manual;

	out = new class'ByteBuffer';
	in = new class'ByteBuffer';
}

event Closed() {
	log("Connection closed!");

	GotoState('NotConnected');
}

event Tick(float DeltaTime) {
	local byte buf[255];
	local byte next;
	local int read;

	if (IsDataPending()) {
		in.compact();
		do {
			read = ReadBinary(Min(in.remaining(), 255), buf);
			if (read > 0) in.putBytes(buf, 0, read);
		} until (read == 0 || !in.hasRemaining())
		in.flip();
	}

	if (in.hasRemaining()) {
		next = in.get();
		if (((1 << 4) & next) > 0 && ((1 << 6) & next) > 0 && ((1 << 7) & next) > 0) { // PINGRESP message
			pingAck(in);
		} else if (((1 << 4) & next) > 0 && ((1 << 5) & next) > 0) { // PUBLISH message
			published(in, next);
		} else if (((1 << 4) & next) > 0 && ((1 << 7) & next) > 0) { // SUBACK message
			subscribeAck(in);
		} else if (((1 << 5) & next) > 0) { // CONNACK message
			connectAck(in);
		} else if (((1 << 6) & next) > 0) { // PUBACK message
			publishAck(in);
		}
	}
}

event connectAck(ByteBuffer buf) {
	warn("Received connection ack when not connecting!");
}

function subscribe(String topic) {
	warn("Cannot subscribe, not connected.");
}

event subscribeAck(ByteBuffer buf) {
	warn("Received subscription ack when not connected!");
}

function publish(String topic, String message) {
	warn("Cannot publish, not connected.");
}

event publishAck(ByteBuffer buf) {
	warn("Received publish ack when not connected!");
}

event published(ByteBuffer buf, byte header) {
	warn("Received published when not connected!");
}

event disconnected(ByteBuffer buf) {
	warn("Received disconnected when not connected!");
}

function disconnect(byte reasonCode) {
	warn("Cannot disconnect when not connected!");
}

function ping() {
	warn("Cannot send ping, not connected.");
}

event pingAck(ByteBuffer buf) {
	warn("Received ping ack when not connected!");
}

function setLengthAndSend(ByteBuffer send) {
		local int was;

		// NOTE assumes mark is at the position we want to set the length at

		//
		// set length and send
		was = out.getPosition();
		out.reset(); // return to mark
		out.putVarInt(was - out.getPosition() - 1);
		out.setPosition(was);
		out.flip();

		sendBuffer(out);
}

function sendBuffer(ByteBuffer send) {
	local byte b[255];
	local int len;

	while (send.hasRemaining()) {
		len = send.getBytes(b, 255);
		SendBinary(len, b);
	}
}

auto state NotConnected {

	function BeginState() {
		log("MQTT client is not connected");

		connect();
	}

	function connect() {
		packetIdent = 0; // reset our packet identifier

    // initiate connection process by resolving the host
    Resolve(mqttHost);
	}

	event Resolved(IpAddr Addr) {
    log("Resolved host " $ mqttHost $ " = " $ Addr.Addr);
    Addr.port = mqttPort;

  	if (BindPort() == 0) {
  		warn("Failed to bind client port.");
  		return;
  	}

  	if (Open(Addr)) {
  		log("Connected!");
  	} else {
  		warn("Connection failed!");
  	}
  }

  event ResolveFailed() {
  	warn("Failed to resolve host " $ mqttHost);
  }

  event Opened() {
  	log("Connection opened!");

  	in.clear();
  	out.clear();

  	GotoState('Connecting');
  }
}

state Connecting {

	function BeginState() {
		log("In Connecting state");

		keepAlive = sessionTtl;

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
		out.put(connectFlags(false, false, false, 0, false, true)); // connect flags - NOTE: wills not actually supported
		out.putShort(sessionTtl); // keep-alive interval seconds

		//
		// properties - FIXME could be an additional buffer, but just pre-calculating the size now since this is simplistic
		out.putVarInt(5);
		// max packet size property
		out.put(39);
		out.putInt(in.CAPACITY); // max packet to buffer capacity

		//
		// payload
		out.putString(clientIdent); // client identifier

		//
		// send
		setLengthAndSend(out);
	}

	event connectAck(ByteBuffer buf) {
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
				case 0x11: // Session Expiry Interval
				  // 4 byte int
				  log("Session Expiry Interval: " $ buf.getInt());
				  break;
				case 0x21: // Receive Maximum
				  // 2 byte short
				  log("Receive Maximum: " $ buf.getShort());
				  break;
				case 0x24: // Maximum QoS
				  // 1 byte
				  log("Maximum QoS: " $ buf.get());
				  break;
				case 0x25: // Retain Available
				  // 1 byte
				  log("Retain Available: " $ buf.get());
				  break;
				case 0x27: // Maximum Packet Size
				  // 2 byte short
				  log("Maximum Packet Size: " $ buf.getShort());
				  break;
				case 0x18: // Assigned Client Identifier
				  // variable length string
				  clientIdent = buf.getString();
				  log("Assigned Client Identifier: " $ clientIdent);
				  break;
				case 0x22: // Topic Alias Maximum
				  // 2 byte short
				  log("Topic Alias Maximum: " $ buf.getShort());
				  break;
				case 0x1f: // Reason String
					log("Reason String: " $ buf.getString());
				  break;
				case 0x26: // User Property, repeats
					log("User Property name : " $ buf.getString());
					log("User Property value: " $ buf.getString());
				  break;
				case 0x28: // Wildcard Subscription Available
				  // 1 byte
				  log("Wildcard Subscription Available: " $ buf.get());
				  break;
				case 0x29: // Subscription Identifiers Available
				  // 1 byte
				  log("Subscription Identifiers Available: " $ buf.get());
				  break;
				case 0x2a: // Shared Subscription Available
				  // 1 byte
				  log("Shared Subscription Available: " $ buf.get());
				  break;
				case 0x13: // Server Keep Alive
				  // 2 byte short
				  keepAlive = buf.getShort();
				  log("Server Keep Alive: " $ keepAlive);
				  break;
				case 0x1a: // Response Information
				  log("Response Information: " $ buf.getString());
				  break;
				case 0x1a: // Server Reference
				  log("Server Reference: " $ buf.getString());
				  break;
				case 0x15: // Authentication Method
				  log("Authentication Method: " $ buf.getString());
				  break;
				case 0x16: // Authentication Data
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

	function byte connectFlags(bool hasUserName, bool hasPassword, bool willRetain, byte willQos, bool willFlag, bool cleanStart) {
		local byte b;

		b = 0;
		if (hasUserName) 	b = b | (1 << 7);
		if (hasPassword) 	b = b | (1 << 6);
		if (willRetain) 	b = b | (1 << 5);
		if (willQos == 2)	b = b | (1 << 4);
		if (willQos == 1)	b = b | (1 << 3);
		if (willFlag) 		b = b | (1 << 2);
		if (cleanStart) 	b = b | (1 << 1);
		// final bit reserved

		return b;
	}

}

state Connected {

	function BeginState() {
		log("In Connected state");

		// set the keep-alive/ping timer.
		// we ping twice as frequently as the session TTL to allow some time margin.
		// this is not a repeating timer - we schedule the timer again once we receive an ack
		SetTimer(keepAlive / 2, False);
		Subscribe("lol");
	}

	event Timer() {
		ping();
	}

	function subscribe(String topic) {
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
		out.put((1 << 0)); // subscription options - qos 1 supported

		//
		// send
		setLengthAndSend(out);
	}

	event subscribeAck(ByteBuffer buf) {
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
				case 0x26: // User Property, repeats
					log("User Property name : " $ buf.getString());
					log("User Property value: " $ buf.getString());
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

		publish("lol", "hello world!");
	}

	function publish(String topic, String message) {
			log("Publishing to topic " $ topic);

  		out.compact();

  		//
  		// packet header
  		out.put((1 << 5) | (1 << 4)); // publish message identifier
  		out.mark(); // remember position, we need to return here to set the length
  		out.put(0); // the length will go here after we construct the body

  		//
  		// publish header
  		out.putString(topic);
  		out.putShort(++packetIdent); // packet identifier - ack should match this

  		//
  		// publish properties
  		out.put(2); // properties length - length FIXME maybe
  		// payload format indicator: set to string
  		out.put(0x01); // property identifier
  		out.put(0x01); // value - string

			//
			// publish payload
			if (out.putString(message) < 0) {
				warn("Message was too large to publish, not sending");
				return;
			}

  		//
  		// send
  		setLengthAndSend(out);
	}

	event published(ByteBuffer buf, byte header) {
		local byte prop, qos;
		local int len, propsLen, ident;
		local String topic, payload;
		local bool isDupe, isRetained;

		log("Got a message!");

		isDupe = ((1 << 3) & header) > 0;
		isRetained = ((1 << 0) & header) > 0;
		if (((1 << 1) & header) > 0) qos = 1;
		else if (((1 << 2) & header) > 0) qos = 2;

		len = buf.getVarInt();
		len += buf.getPosition();

		topic = buf.getString();

		if (qos > 0) {
			ident = buf.getShort();
			if (qos > 1) {
				disconnect(0x9B); // disconnect - QoS not supported
				return;
			}
		}

		propsLen = buf.getVarInt();
		propsLen += buf.getPosition();
		while (buf.getPosition() < propsLen) {
			prop = buf.get();
			switch (prop) {
				case 0x01: // Payload Format Indicator
					// 1 byte
					log("Payload Format Indicator: " $ buf.get());
					break;
				case 0x02: // Message Expiry Interval
					// 4 byte int
					log("Message Expiry Interval: " $ buf.getInt());
					break;
				case 0x23: // Topic Alias
					// 2 byte short
					log("Topic Alias: " $ buf.getShort());
					break;
				case 0x08: // Response Topic
					log("Response Topic: " $ buf.getString());
					break;
				case 0x09: // Correlation Data
					// ... byte binary data... how long?
					log("Correlation Data: " $ buf.getString());
					break;
				case 0x26: // User Property, repeats
					log("User Property name: " $ buf.getString());
					log("User Property value: " $ buf.getString());
					break;
				case 0x0B: // Subscription Identifier
					// variable int
					log("Subscription Identifier: " $ buf.getVarInt());
					break;
				case 0x03: // Content Type
					log("Content Type: " $ buf.getString());
					break;
				default:
					warn("received unknown property identifier: " $ prop);
					return;
			}
		}

		payload = "";
		while (buf.getPosition() < len) {
			// this is the payload
			payload = payload $ Chr(buf.get());
		}

		log("Received publish payload: " $ payload);

		if (qos == 1) sendPublishAck(ident, 0);
	}

	function sendPublishAck(int ident, byte reasonCode) {
		log("Sending publish ack for packet " $ ident);

		out.compact();

		//
		// packet header
		out.put(1 << 6); // puback message identifier
		out.mark(); // remember position, we need to return here to set the length
		out.put(0); // the length will go here after we construct the body

		//
		// puback header
		out.putShort(ident); // packet identifier
		out.put(reasonCode); // packet identifier
		out.put(0); // properties length - 0, none

		//
		// properties
		// no properties included. options are:
		// 0x1F: reason string
		// 0x26: user property (string key/value pair)

		//
		// send
		setLengthAndSend(out);
	}

	function disconnect(byte reasonCode) {
		warn("Disconnecting with reason code " $ reasonCode);

		out.compact();

		//
		// packet header
		out.put((1 << 7) | (1 << 6) | (1 << 5)); // disconnect message identifier
		out.mark(); // remember position, we need to return here to set the length
		out.put(0); // the length will go here after we construct the body

		//
		// disconnect header
		out.put(reasonCode); // reason code identifier
		out.put(0); // properties length - 0, none

		//
		// properties
		// no properties included. options are:
		// 0x11: Session Expiry Interval
		// 0x1F: Reason String
		// 0x26: User Property
		// 0x1C: Server Reference

		//
		// send
		setLengthAndSend(out);
	}

	function ping() {
		log("Send ping");

		pingTime = Level.TimeSeconds;

		out.compact();

		//
		// packet header
		out.put((1 << 7) | (1 << 6)); // pingreq message identifier
		out.put(0); // zero length payload

		out.flip();

		sendBuffer(out);
	}

	function pingAck(ByteBuffer buf) {
		log("Received ping response in " $ (Level.TimeSeconds - pingTime) $ "s");

		// null byte
		if (buf.get() != 0) {
			warn("Error, received a value in ping response where none was expected");
			disconnect(0x82); // protocol error
		}

		SetTimer(keepAlive / 2, False);
	}
}

defaultproperties {
	clientIdent="utserver"
  mqttHost="192.168.2.128"
  mqttPort=1883
  sessionTtl=60
}
