class MQTTClientTest extends Mutator;


function PostBeginPlay() {
	log("Hello world");
	Spawn(class'MQTTClient', self);

	ByteBufferTest();
}

function ByteBufferTest() {
	local ByteBuffer buf;
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
}

defaultproperties {
}
