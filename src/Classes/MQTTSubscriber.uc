//=============================================================================
// The MQTTSubscriber acts as an interface between the MQTTClient and custom
// subscription message handlers.
//
// The MQTTSubscriber is intended to be spawned with the MQTTClient as its
// owner, which allows the MQTTClient to then handle topic subscriptions and
// message delivery to MQTTSubscriber instances automatically.
//
// Custom implementations should inherit from this class, and may override the
// following events:
//
// - subscribed()
// - receiveMessage(String topic, String message)
//=============================================================================
class MQTTSubscriber extends Info;

/**
 * Topic filter to subscribe to.
 */
var String topic;

/**
 * If true, request server to send retained messages matching the topic filter
 * when subscribing.
 */
var bool sendRetained;

/**
 * If true, this subscription will not receive published by this client.
 */
var bool noLocal;

// internal state management
var int subscriptionIdent;

event subscribed() {
	log("Subscriber " $ Self $ " subscribed to topic " $ topic);
}

event receiveMessage(String topic, String message) {
	log("Subscriber " $ Self $ " received message on topic " $ topic $ ": " $ message);
}

defaultproperties {
	topic="utserver/#"
	noLocal=true
	sendRetained=false
}
