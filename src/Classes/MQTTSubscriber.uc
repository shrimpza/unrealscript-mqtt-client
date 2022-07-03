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

var String topic;
var int subscriptionIdent;

event subscribed() {
	log("Subscriber " $ Self $ " subscribed to topic " $ topic);
}

event receiveMessage(String topic, String message) {
	log("Subscriber " $ Self $ " received message on topic " $ topic $ ": " $ message);
}

defaultproperties {
	topic="utserver/#"
}
