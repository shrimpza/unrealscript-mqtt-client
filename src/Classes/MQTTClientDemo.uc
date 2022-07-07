class MQTTClientDemo extends Mutator
	config;

var config String topic;

var private MQTTClient mqtt;
var private MQTTSubscriber sub;

function PostBeginPlay() {
	mqtt = Spawn(class'MQTTClient', Self);
//	sub = Spawn(class'MQTTSubscriber', mqtt);
	Level.Game.RegisterDamageMutator(Self);
}

event Trigger(Actor Other, Pawn EventInstigator) {
	// the MQTTClient will trigger its owner when it has connected successfully
	if (other == mqtt) mqtt.publish(topic, "start/" $ Level.TimeSeconds $ "/" $ Level.Game.GameName $ "/" $ Level.Title);
}

function bool HandleEndGame() {
	mqtt.publish(topic, "end/" $ Level.TimeSeconds $ "/" $ Level.Game.GameName $ "/" $ Level.Title);

	return Super.HandleEndGame();
}

function ModifyLogin(out class<playerpawn> SpawnClass, out string Portal, out string Options) {
	mqtt.publish(topic, "join/" $ Level.TimeSeconds $ "/" $ Level.Game.ParseOption(Options, "Name"));

	if (NextMutator != None) NextMutator.ModifyLogin(SpawnClass, Portal, Options);
}

function ScoreKill(Pawn Killer, Pawn Other) {
	local String killerName, otherName, weaponName;

	if (Killer != None) {
		killerName = Killer.GetHumanName();
		if (Killer.Weapon != None) weaponName = Killer.Weapon.ItemName;
		else weaponName = "None";
	} else {
		killerName = "None";
		weaponName = "None";
	}

	if (Other != None) otherName = Other.GetHumanName();
	else otherName = "None";

	mqtt.publish(topic, "kill/" $ Level.TimeSeconds $ "/" $ killerName $ "/" $ otherName $ "/" $ weaponName);

	Super.ScoreKill(Killer, Other);
}

function MutatorTakeDamage(out int ActualDamage, Pawn Victim, Pawn InstigatedBy, out Vector HitLocation, out Vector Momentum, name DamageType) {
	local String victimName, instigatorName, weaponName;

	if (Victim != None) victimName = Victim.GetHumanName();
	else victimName = "None";

	if (InstigatedBy != None) {
		instigatorName = InstigatedBy.GetHumanName();
		if (InstigatedBy.Weapon != None) weaponName = InstigatedBy.Weapon.ItemName;
		else weaponName = "None";
	} else {
		instigatorName = "None";
		weaponName = "None";
	}

	mqtt.publish(topic, "dmg/" $ Level.TimeSeconds $ "/" $ instigatorName $ "/" $ victimName $ "/" $ weaponName $ "/" $ DamageType $ "/" $ ActualDamage);

	Super.MutatorTakeDamage(ActualDamage, Victim, InstigatedBy, HitLocation, Momentum, DamageType);
}

defaultproperties {
	topic="utserver/feed"
}
