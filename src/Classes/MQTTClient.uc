class MQTTClient extends TCPLink
	config;

/*
 * connection properties
 */
var config String mqttHost;			// The MQTT host to connect to
var config int mqttPort;				// The MQTT port to connect to
var config int sessionTtl;			// Session TTL, after no activity for this long the connection will close. Pings are used to keep alive.
var config String mqttUser;			// MQTT user to authenticate with, if required
var config String mqttPass;			// MQTT password to authenticate with, if required
var config String clientIdent;	// unique client identifier

/*
 * misc properties
 */
var config bool debugLog;


// private state management
var private transient int packetIdent;
var private int keepAlive; // interval between pings, set to sessionTtl, or overridden by server
var private float pingTime; // RTT for ping requests

// i/o buffers
var private transient ByteBuffer out;
var private transient ByteBuffer in;

// pending subscriber management
var private array<MQTTSubscriber> newSubscribers;

static final operator(18) int % (int A, int B) {
	return A - (A / B) * B;
}

function debug(coerce String msg) {
	if (debugLog) log("[MQTT Debug] " $ msg);
}

function PreBeginPlay() {
	Super.PreBeginPlay();

	// these need to be set at runtime
	LinkMode = MODE_Binary;
	ReceiveMode = RMODE_Manual;

	out = new class'ByteBuffer';
	in = new class'ByteBuffer';
}

function bool IsConnectionEstablished() {
	return IsConnected() && isInState('Connected');
}

/**
 * Called when an actor is spawned with this as the owner.
 *
 * In the case of an MQTTSubscriber, we create a topic subscription
 * to begin receiving messages on its behalf.
 */
event GainedChild(Actor other) {
	// if is a MQTTSubscriber, it's a new subscription
	local MQTTSubscriber subscriber;

	Super.GainedChild(other);

	subscriber = MQTTSubscriber(other);
	if (subscriber == None) return;

	// at this point, the child/subscriber has not been fully initialised, so we enqueue
	// its actual subscription for the next tick.
	newSubscribers.Insert(newSubscribers.Length, 1);
	newSubscribers[newSubscribers.Length- 1 ] = subscriber;
}

/**
 * Called when a child actor is destroyed or detached from this one.
 *
 * In the case of an MQTTSubscriber, if it was the only remaining
 * subscriber on a specific topic, also unsubscribe from that topic.
 */
event LostChild(Actor other) {
	// if is a MQTTSubscriber, unsubscribe
	local MQTTSubscriber subscriber, it;

	Super.LostChild(other);

	subscriber = MQTTSubscriber(other);
	if (subscriber == None) return;

	ForEach ChildActors(class'MQTTSubscriber', it) {
		// there's still another active subscriber on this topic - so to not unsubscribe
		if (it != subscriber && it.topic == subscriber.topic) return;
	}

	if (IsConnectionEstablished()) unsubscribe(subscriber.topic);
}

event Closed() {
	log("[MQTT] Connection closed!");

	Super.Closed();

	GotoState('NotConnected');
}

/**
 * On each tick, check if there is outstanding data waiting to be read, and if
 * there is, fill our incoming buffer with as much as is available.
 *
 * Once reading is complete, attempt to identify the packet type, and hand off
 * to appropriate function for processing.
 */
event Tick(float DeltaTime) {
	local byte buf[255];
	local byte next;
	local int read, i;

	if (!IsConnected()) return;

	if (IsDataPending()) {
		in.compact();
		do {
			read = ReadBinary(Min(in.remaining(), 255), buf);
			if (read > 0) in.putBytes(buf, 0, read);
		} until (read == 0 || !in.hasRemaining())
		in.flip();
	}

	while (in.hasRemaining()) {
		next = in.get();
		if (next == -1) return;
		if (((1 << 7) & next) > 0 && ((1 << 5) & next) > 0 && ((1 << 4) & next) > 0) { // UNSUBACK message
			unsubscribeAck(in);
		} else if (((1 << 4) & next) > 0 && ((1 << 6) & next) > 0 && ((1 << 7) & next) > 0) { // PINGRESP message
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

	// set up new subscriptions, if any
	if (newSubscribers.Length > 0) {
		for (i = 0; i < newSubscribers.Length; i++) {
			if (IsConnectionEstablished()) subscribe(newSubscribers[i].topic);
		}
		newSubscribers.Remove(0, newSubscribers.Length);
	}
}

event connectAck(ByteBuffer buf) {
	warn("Received connection ack when not connecting!");
}

function subscribe(String topic, optional MQTTSubscriber subscriber) {
	warn("Cannot subscribe, not connected.");
}

event subscribeAck(ByteBuffer buf) {
	warn("Received subscription ack when not connected!");
}

function unsubscribe(String topic) {
	warn("Cannot unsubscribe, not connected.");
}

event unsubscribeAck(ByteBuffer buf) {
	warn("Received unsubscribe ack when not connected!");
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

/**
 * A helper function which will populate an MQTT packet length indicator prior
 * to sending, and then send the packet.
 */
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

/**
 * A helper function which writes the provided buffer in 255 byte chunks as
 * required by the SendBinary implementation.
 */
function sendBuffer(ByteBuffer send) {
	local byte b[255];
	local int len;

	while (send.hasRemaining()) {
		len = send.getBytes(b, 255);
		SendBinary(len, b);
	}
}

/**
 * Upon entering the NotConnected state, the MQTT host is resolved, and a
 * connection attempt is started.
 *
 * Successfully resolving the host and opening the socket connection will
 * advance to the Connecting state.
 */
auto state NotConnected {

	function BeginState() {
		debug("Client is not connected");

		connect();
	}

	function connect() {
		log("[MQTT] Client connecting to " $ mqttHost $ ":" $ mqttPort);

		packetIdent = 0; // reset our packet identifier

		// initiate connection process by resolving the host
		Resolve(mqttHost);
	}

	event Resolved(IpAddr Addr) {
		Addr.port = mqttPort;

		if (BindPort() == 0) {
			warn("Failed to bind client port.");
			return;
		}

		if (Open(Addr)) {
			debug("Connected!");
		} else {
			warn("Connection failed!");
		}
	}

	event ResolveFailed() {
		warn("Failed to resolve host " $ mqttHost);
	}

	event Opened() {
		debug("Connection opened!");

		in.clear();
		out.clear();

		GotoState('Connecting');
	}
}

/**
 * Entering the Connecting state, a connection message will be sent to the
 * MQTT host, and on successful receipt of a connection ACK, will advance to
 * the Connected state.
 */
state Connecting {

	function BeginState() {
		debug("In Connecting state");

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
		out.put(connectFlags(mqttUser != "", mqttPass != "", false, 0, false, true)); // connect flags - NOTE: wills not actually supported
		out.putShort(sessionTtl); // keep-alive interval seconds

		//
		// properties - FIXME could be an additional buffer, but just pre-calculating the size now since this is simplistic
		out.putVarInt(5);
		// max packet size property
		out.put(0x27);
		out.putInt(in.CAPACITY); // max packet to buffer capacity

		//
		// payload
		out.putString(clientIdent); // client identifier

		if (mqttUser != "") out.putString(mqttUser); // user name
		if (mqttPass != "") out.putString(mqttPass); // password

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
					debug("Session Expiry Interval: " $ buf.getInt());
					break;
				case 0x21: // Receive Maximum
					// 2 byte short
					debug("Receive Maximum: " $ buf.getShort());
					break;
				case 0x24: // Maximum QoS
					// 1 byte
					debug("Maximum QoS: " $ buf.get());
					break;
				case 0x25: // Retain Available
					// 1 byte
					debug("Retain Available: " $ buf.get());
					break;
				case 0x27: // Maximum Packet Size
					// 2 byte short
					debug("Maximum Packet Size: " $ buf.getShort());
					break;
				case 0x18: // Assigned Client Identifier
					// variable length string
					clientIdent = buf.getString();
					debug("Assigned Client Identifier: " $ clientIdent);
					break;
				case 0x22: // Topic Alias Maximum
					// 2 byte short
					debug("Topic Alias Maximum: " $ buf.getShort());
					break;
				case 0x1f: // Reason String
					debug("Reason String: " $ buf.getString());
					break;
				case 0x26: // User Property, repeats
					debug("User Property name : " $ buf.getString());
					debug("User Property value: " $ buf.getString());
					break;
				case 0x28: // Wildcard Subscription Available
					// 1 byte
					debug("Wildcard Subscription Available: " $ buf.get());
					break;
				case 0x29: // Subscription Identifiers Available
					// 1 byte
					debug("Subscription Identifiers Available: " $ buf.get());
					break;
				case 0x2a: // Shared Subscription Available
					// 1 byte
					debug("Shared Subscription Available: " $ buf.get());
					break;
				case 0x13: // Server Keep Alive
					// 2 byte short
					keepAlive = buf.getShort();
					debug("Server Keep Alive: " $ keepAlive);
					break;
				case 0x1a: // Response Information
					debug("Response Information: " $ buf.getString());
					break;
				case 0x1a: // Server Reference
					debug("Server Reference: " $ buf.getString());
					break;
				case 0x15: // Authentication Method
					debug("Authentication Method: " $ buf.getString());
					break;
				case 0x16: // Authentication Data
					// ... byte binary data... everything until end of properties?
					buf.setPosition(propsLen);
					break;
				default:
					warn("[mqtt] Received unknown property identifier: " $ prop);
					return;
			}
		}

		switch (reasonCode) {
			case 0x00:
				GotoState('Connected');
				// returning here, since we'll automatically fall through to the failed state for all other cases
				return;
			case 0x80:
				warn("Unspecified error");
				break;
			case 0x81:
				warn("Malformed Packet");
				break;
			case 0x82:
				warn("Protocol Error");
				break;
			case 0x83:
				warn("Implementation specific error");
				break;
			case 0x84:
				warn("Unsupported Protocol Version");
				break;
			case 0x85:
				warn("Client Identifier not valid");
				break;
			case 0x86:
				warn("Bad User Name or Password");
				break;
			case 0x87:
				warn("Not Authorised");
				break;
			case 0x88:
				warn("Server unavailable");
				break;
			case 0x89:
				warn("Server busy");
				break;
			case 0x8A:
				warn("Banned");
				break;
			case 0x8C:
				warn("Bad authentication method");
				break;
			case 0x90:
				warn("Topic Name invalid");
				break;
			case 0x95:
				warn("Packet too large");
				break;
			case 0x97:
				warn("Quota exceeded");
				break;
			case 0x99:
				warn("Payload format invalid");
				break;
			case 0x9A:
				warn("Retain not supported");
				break;
			case 0x9B:
				warn("QoS not supported");
				break;
			case 0x9C:
				warn("Use another server");
				break;
			case 0x9D:
				warn("Server moved");
				break;
			case 0x9F:
				warn("Connection rate exceeded");
				break;
			default:
				warn("Unknown reason code on connect: " $ reasonCode);
		}
		GotoState('Failed');
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

/**
 * While in the Connected state, topic subscriptions may be created, messages
 * may be published, and incoming messages will be received and delegated to
 * appropriate subscribers.
 *
 * While connected, periodic ping requests will be sent, to keep the connection
 * alive, per the server's keep alive interval (and the configured sessionTtl).
 *
 * If the connection drops or is closed, we will return to the NotConnected
 * state in an attempt to re-establish the connection.
 */
state Connected {

	function BeginState() {
		local MQTTSubscriber sub;

		log("[MQTT] Client has connected");

		// set the keep-alive/ping timer.
		// we ping twice as frequently as the session TTL to allow some time margin.
		// this is not a repeating timer - we schedule the timer again once we receive an ack
		SetTimer(keepAlive / 2, False);

		// if there were subscribers waiting to subscribe (they were created before the
		// connection was up), subscribe to topics now.
		ForEach ChildActors(class'MQTTSubscriber', sub) {
			subscribe(sub.topic);
		}

		// notify owner by way of trigger, so it knows we're connected
		if (Owner != None) Owner.Trigger(Self, None);
	}

	event Timer() {
		ping();
	}

	function subscribe(String topic, optional MQTTSubscriber subscriber) {
		local int ident;

		if (topic == "") {
			warn("Cannot subscribe to empty topic name");
			return;
		}

		ident = ++packetIdent;

		log("[MQTT] Subscribing to topic " $ topic);

		if (subscriber != None) subscriber.subscriptionIdent = ident;

		out.compact();

		//
		// packet header
		out.put((1 << 7) | (1 << 1)); // subscribe message identifier
		out.mark(); // remember position, we need to return here to set the length
		out.put(0); // the length will go here after we construct the body

		//
		// subscription header
		out.putShort(ident); // packet identifier, can use to correlate back to subscriber for Ack
		out.put(0); // properties length - 0, none

		//
		// subscriptions
		out.putString(topic); // subscription name
		if (subscriber != None) {
			out.put(subscribeFlags(1, subscriber.noLocal, false, subscriber.sendRetained, true));
		} else {
			// default options
			out.put(subscribeFlags(1, false, false, false, false));
		}

		//
		// send
		setLengthAndSend(out);
	}

	function byte subscribeFlags(byte qosLevel, bool noLocal, bool retainAsPublished, bool sendRetained, bool sendRetainedNewSubsOnly) {
		local byte b;

		b = 0;
		// bits 6 and 7 are reserved
		if (!sendRetained) 			b = b | (1 << 5);
		if (sendRetained && sendRetainedNewSubsOnly) b = b | (1 << 4);
		if (retainAsPublished) 	b = b | (1 << 3);
		if (noLocal) 						b = b | (1 << 2);
		if (qosLevel == 2)			b = b | (1 << 1);
		if (qosLevel == 1)			b = b | (1 << 0);

		return b;
	}

	event subscribeAck(ByteBuffer buf) {
		local byte reasonCode, prop;
		local int len, propsLen, ident;
		local MQTTSubscriber sub;

		debug("Subscribed!");

		len = buf.getVarInt();
		len += buf.getPosition();
		ident = buf.getShort();
		propsLen = buf.getVarInt();
		propsLen += buf.getPosition();
		while (buf.getPosition() < propsLen) {
			prop = buf.get();
			switch (prop) {
				case 0x26: // User Property, repeats
					debug("User Property name : " $ buf.getString());
					debug("User Property value: " $ buf.getString());
					break;
				default:
					warn("received unknown property identifier: " $ prop);
					return;
			}
		}

		while (buf.getPosition() < len) {
			reasonCode = buf.get();
			debug("reason code: " $ reasonCode);
		}

		ForEach ChildActors(class'MQTTSubscriber', sub) {
			if (sub.subscriptionIdent == ident) sub.subscribed();
		}
	}

	function unsubscribe(String topic) {
		log("[MQTT] Unsubscribe from topic " $ topic);

		out.compact();

		//
		// packet header
		out.put((1 << 7) | (1 << 5) | (1 << 1)); // unsubscribe message identifier
		out.mark(); // remember position, we need to return here to set the length
		out.put(0); // the length will go here after we construct the body

		//
		// subscription header
		out.putShort(++packetIdent); // packet identifier - ack should match this
		out.put(0); // properties length - 0, none

		//
		// subscriptions
		out.putString(topic); // subscription name

		//
		// send
		setLengthAndSend(out);
	}

	event unsubscribeAck(ByteBuffer buf) {
		local byte reasonCode, prop;
		local int len, propsLen, ident;

		debug("Unsubscribed");

		len = buf.getVarInt();
		len += buf.getPosition();
		ident = buf.getShort();
		if (ident != packetIdent) warn("Received packet ident " $ ident $ " but was expecting " $ packetIdent);
		propsLen = buf.getVarInt();
		propsLen += buf.getPosition();
		while (buf.getPosition() < propsLen) {
			prop = buf.get();
			switch (prop) {
				case 0x1f: // Reason String
					debug("Reason String: " $ buf.getString());
					break;
				case 0x26: // User Property, repeats
					debug("User Property name: " $ buf.getString());
					debug("User Property value: " $ buf.getString());
					break;
				default:
					warn("received unknown property identifier: " $ prop);
					return;
			}
		}

		while (buf.getPosition() < len) {
			reasonCode = buf.get();
			debug("reason code: " $ reasonCode);
		}
	}

	function publish(String topic, String message) {
		if (topic == "") {
			warn("Cannot publish to empty topic name");
			return;
		}

		debug("Publishing to topic " $ topic $ ": " $ message);

		out.compact();

		//
		// packet header
		out.put((1 << 5) | (1 << 4)); // publish message identifier
		out.mark(); // remember position, we need to return here to set the length
		out.put(0); // the length will go here after we construct the body

		//
		// publish header
		out.putString(topic);
		// if qos, include packet ident for ack
		//out.putShort(++packetIdent); // packet identifier - ack should match this

		//
		// publish properties
		out.putVarInt(2); // properties length - length FIXME maybe
		// payload format indicator: set to string
		out.put(0x01); // property identifier
		out.put(0x01); // value - string

		//
		// publish payload
		if (out.putString(message, true) < 0) {
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
		local MQTTSubscriber sub;
		local int strPos;

		debug("Got a message!");

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
					debug("Payload Format Indicator: " $ buf.get());
					break;
				case 0x02: // Message Expiry Interval
					// 4 byte int
					debug("Message Expiry Interval: " $ buf.getInt());
					break;
				case 0x23: // Topic Alias
					// 2 byte short
					debug("Topic Alias: " $ buf.getShort());
					break;
				case 0x08: // Response Topic
					debug("Response Topic: " $ buf.getString());
					break;
				case 0x09: // Correlation Data
					// ... byte binary data... how long?
					debug("Correlation Data: " $ buf.getString());
					break;
				case 0x26: // User Property, repeats
					debug("User Property name: " $ buf.getString());
					debug("User Property value: " $ buf.getString());
					break;
				case 0x0B: // Subscription Identifier
					// variable int
					debug("Subscription Identifier: " $ buf.getVarInt());
					break;
				case 0x03: // Content Type
					debug("Content Type: " $ buf.getString());
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

		debug("Received publish on topic " $ topic $ ": " $ payload);

		ForEach ChildActors(class'MQTTSubscriber', sub) {
			if (sub.topic == topic || sub.topic == "#") sub.receiveMessage(topic, payload);
			else {
				// attempt to match on wildcard subscriptions

				// multi-level wildcard match - anything in the path following the wildcard is to be delivered
				strPos = InStr(sub.topic, "/#");
				if (strPos > -1 && InStr(topic, "/") > -1) {
					if (Left(sub.topic, strPos) == Left(topic, strPos)) {
						sub.receiveMessage(topic, payload);
					}
					continue;
				}

				// single-level wildcard matches - only match things at the level the wildcard is on
				strPos = InStr(sub.topic, "+");
				if (strPos > -1) {
					// root level matches
					if (strPos == 0 && InStr(topic, "/") == -1) {
						sub.receiveMessage(topic, payload);
					}
				}
			}
		}

		if (qos == 1) sendPublishAck(ident, 0);
	}

	function sendPublishAck(int ident, byte reasonCode) {
		debug("Sending publish ack for packet " $ ident);

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
		debug("Send ping");

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
		debug("Received ping response in " $ (Level.TimeSeconds - pingTime) $ "s");

		// null byte
		if (buf.get() != 0) {
			warn("Error, received a value in ping response where none was expected");
			disconnect(0x82); // protocol error
		}

		SetTimer(keepAlive / 2, False);
	}
}

state Failed {
	function BeginState() {
		warn("Entering failed state, will not attempt a reconnection");
		Disable('Tick');
		Disable('Timer');
	}
}

defaultproperties {
	clientIdent="utserver"
	mqttHost="192.168.2.128"
	mqttPort=1883
	mqttUser="unreal"
	mqttPass="blue52"
	sessionTtl=60
	debugLog=true
}
