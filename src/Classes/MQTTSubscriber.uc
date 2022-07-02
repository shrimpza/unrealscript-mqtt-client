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

//var private String topic;
//var private MQTTClient mqtt;

function PostBeginPlay() {
	SetTimer(0.1, False);
}

event Timer() {
	local MQTTClient mqtt;
	mqtt = MQTTClient(Owner);
	if (mqtt != None) {
		log("My Tag is " $ tag);
		mqtt.addSubscriber(String(Tag), Self);
	}
}

event subscribed(String topic) {
	log("Subscriber " $ Self $ " subscribed to topic " $ topic);
}

event receiveMessage(String topic, String message) {
	log("Subscriber " $ Self $ " received message on topic " $ topic $ ": " $ message);
}

defaultproperties {
}
