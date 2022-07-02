//=============================================================================
// The MQTTSubscriber acts as an interface between the MQTTClient and custom
// subscription message handlers.
//
// Custom implementations may inherit from this class, and override the
// following events:
//
// - subscribed(String topic)
// - receiveMessage(String topic, String message)
//=============================================================================
class MQTTSubscriber extends Info;

var String topic;
var int subscriptionIdent;

function PostBeginPlay() {
	local MQTTClient mqtt;
	mqtt = MQTTClient(Owner);
	if (mqtt != None) mqtt.newSubscriber(Self);
}

event subscribed() {
	log("Subscriber " $ Self $ " subscribed to topic " $ topic);
}

event receiveMessage(String topic, String message) {
	log("Subscriber " $ Self $ " received message on topic " $ topic $ ": " $ message);
}

defaultproperties {
	topic="utserver"
}
