class MQTTClientTest extends Mutator;


function PostBeginPlay() {
	log("Hello world");
	Spawn(class'MQTTClient', self);
}

defaultproperties {
}
