class MQTTClientTest extends Mutator;

var private MQTTClient mqtt;
var private MQTTSubscriber sub;

function PostBeginPlay() {
	log("Hello world");
	mqtt = Spawn(class'MQTTClient', self);

	sub = Spawn(class'MQTTSubscriber', mqtt);

	SetTimer(10, False);

	ByteBufferTest();
}

event Timer() {
	if (sub != None) {
		sub.Destroy();
		sub = None;
	}
}

function ByteBufferTest() {
	local ByteBuffer buf, other;
	local byte b[255];
	local int i;

	buf = new class'ByteBuffer';
	buf.clear();

	assert(buf.hasRemaining());
	assert(buf.remaining() == 1024);

	for (i = 0; i < 10; i++) b[i] = i;

	assert(buf.putBytes(b, 0, 10) == 10);
	assert(buf.hasRemaining());
	assert(buf.remaining() == 1014);

	buf.flip();
	assert(buf.remaining() == 10);
	for (i = 0; i < 10; i++) assert(buf.get() == i);
	assert(!buf.hasRemaining());

	buf.compact();
	assert(buf.remaining() == 1024);
	for (i = 0; i < 10; i++) b[i] = i + 100;
	assert(buf.putBytes(b, 0, 10) == 10);
	assert(buf.putBytes(b, 0, 10) == 10);
	assert(buf.remaining() == 1004);

	buf.flip();
	assert(buf.remaining() == 20);
	assert(buf.getPosition() == 0);
	assert(buf.get() == 100);
	assert(buf.get() == 101);
	assert(buf.getPosition() == 2);
	assert(buf.remaining() == 18);

	buf.clear();
	assert(buf.remaining() == 1024);
	buf.putString("hello world");
	assert(buf.remaining() == 1024 - 2 - Len("hello world"));
	buf.flip();
	assert(buf.getString() == "hello world");
	assert(!buf.hasRemaining());

	buf.clear();
	for (i = 0; i < 10; i++) b[i] = i + 200;
	assert(buf.putBytes(b, 0, 10) == 10);
	buf.flip();
	assert(buf.remaining() == 10);
	for (i = 0; i < 255; i++) b[i] = 0;
	assert(buf.getBytes(b, 50) == 10);
	assert(buf.remaining() == 0);
	assert(b[0] == 200);
	assert(b[9] == 209);
	assert(buf.getBytes(b, 50) == 0);

	other = new class'ByteBuffer';
	other.clear();
	buf.clear();
	for (i = 0; i < 10; i++) b[i] = i + 100;
	assert(buf.putBytes(b, 0, 10) == 10);
	buf.flip();
	assert(buf.remaining() == 10);
	assert(other.putBuffer(buf) == 10);
	assert(buf.remaining() == 0);
	assert(other.remaining() == 1014);
	other.flip();
	assert(other.remaining() == 10);
	assert(other.get() == 100);
	assert(other.get() == 101);
	assert(other.remaining() == 8);

	buf.clear();
	buf.putShort(223);
	buf.putInt(9001);
	buf.flip();
	assert(buf.getShort() == 223);
	assert(buf.getInt() == 9001);

	buf.clear();
	buf.put(0x2e);
	buf.put(0);
	buf.put(0x20);
	buf.flip();
	log("" $ buf.getVarInt());
	assert(buf.getShort() == 32);

	buf.clear();
	do {
		for (i = 0; i < 255; i++) b[i] = i;
		buf.putBytes(b, 0, Min(buf.remaining(), 255));
	} until (!buf.hasRemaining())
	buf.flip();
	assert(buf.remaining() == 1024);
}

defaultproperties {
}
