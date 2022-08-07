# UnrealScript MQTT Client

A simple MQTT client implemented in UnrealScript for Unreal Tournament 
(possibly works with other Unreal Engine 1 games as well).

The following MQTT protocol features are supported:

- MQTT version 5.0
- Message publishing 
- Message subscriptions with basic topic filter support
- QoS level 1 support
- Basic authentication (username and password)

With these limitations:

- Maximum packet size of 1024 bytes
- Only supports plain text messages (custom or binary formats can be implemented)
- Can't publish retained messages
- Most message, subscription, and connection properties don't do anything 

## Usage

To use the MQTT client in UnrealScript projects, spawn it, owned by one of your
own actors. When it's connected, it will trigger its owner. Eg:

```unrealscript
class MyThing extends Actor;

var private MQTTClient mqtt;

function PostBeginPlay() {
	mqtt = Spawn(class'MQTTClient', Self);
}

event Trigger(Actor Other, Pawn EventInstigator) {
	// the MQTTClient will trigger its owner when it has connected successfully
	if (Other == mqtt) {
		// you may now publish messages
		mqtt.publish("mytopic", "Hello World");
	}
}
```

If you want to subscribe to a topic, you will need to implement a subscriber 
actor which extends `MQTTSubscriber`. 

When spawned, Subscribers should be owned by the `MQTTClient`, thereby allowing
the client to manage the subscriptions based on the actor's lifecycle (eg. 
destroying the actor will cause the client to unsubscribe from a topic it was
using).

You may spawn an `MQTTSubscriber` at any time, it does not need to wait for a
connection to be established - subscriptions will be automatically created if
and when the client connects.

Your `MQTTSubscriber` may implement whatever logic you want to react to 
received messages, or it may simply act as a shim between your code and the 
MQTT Client. Eg:

```unrealscript
class MyTopicSubscriber extends MQTTSubscriber;

event subscribed() {
	log("I'm alive!");
}

event receiveMessage(String topic, String message) {
	log("Got a message on topic " $ topic $ ": " $ message);
	// do interesting things in the game based on the message
}

defaultproperties {
	topic="mytopic/#"
}
```

Then create an instance of it:

```unrealscript
class MyThing extends Actor;

var private MQTTClient mqtt;
var private MyTopicSubscriber subscriber;

function PostBeginPlay() {
	mqtt = Spawn(class'MQTTClient', Self);
	subscriber = Spawn(class'MyTopicSubscriber', mqtt);
}
```

## Configuration

In your game or server's `UnrealTournament.ini` file, append the configuration:

```ini
[MQTTClient.MQTTClient]
mqttHost=broker.hivemq.com
mqttPort=1883
sessionTtl=60
mqttUser=
mqttPass=
clientIdent=utserver
debugLog=false
```

Obviously provide your own private MQTT host if available, otherwise 
[HiveMQ](https://www.hivemq.com/public-mqtt-broker/)'s public broker is handy
for testing - just be sure to use unique topic names, and be aware that 
everything published there is public.

