class ByteBuffer extends Object;

const CAPACITY = 1024;

var private byte buf[CAPACITY];
var private int limit, position, marker, remaining;

/**
 *
 */
function int append(byte incoming[255], int from, int to) {
	local int add, was, i;

	add = to - from;

	if (to <= from || size > 255) {
		warn("Invalid range for from [" $ from $ "] and to [" $ to $ "]: " $ add);
		return -1;
	}

	was = limit;
	for (i = from; from < to && limit < CAPACITY; i++) {
		buf[size++] = incoming[i];
	}

	return limit - was;
}

function compact() {

}

function byte read() {
	if (!hasRemaining(1)) return -1;
	return buf[position++];
}

function int write(byte val) {
	local int was;
	if (!hasCapacity(1)) return -1;
	was = position;

	buf[position++] = val;

	return position - was;
}

function int readShort() {
	if (!hasRemaining(2)) return -1;
	return buf[position++] << 8 | buf[position++];
}

function int writeShort(int val) {
	local int was;
	if (!hasCapacity(2)) return -1;
	was = position;

	buf[position++] = ((val >> 8) & 0xff);
	buf[position++] = val & 0xff;

	return position - was;
}

// TODO readInt

function int writeInt(int val) {
	local int was;
	if (!hasCapacity(4)) return -1;
	was = position;

	buf[position++] = (val & 0xff000000) >> 24;
	buf[position++] = (val & 0x00ff0000) >> 16;
	buf[position++] = (val & 0x0000ff00) >> 8;
	buf[position++] =  val & 0x000000ff;

	return position - was;
}

function String readString() {
	local int len, i;
	local String str;
	if (!hasRemaining(2)) return "";
	len = readShort();

	if (len == -1) return "";

	if (!hasRemaining(len)) {
		position =- 2; // rewind, so we can try again? hax?!
		return "";
	}

	for (i = 0; i < len; i++) {
		str = str $ Chr(buf[position++]);
	}

	return str;
}

function int writeString(String str) {
	local int i, was;
	if (!hasCapacity(2 + Len(str))) return -1;
	was = position;

	writeShort(Len(str));
	for (i = 0; i < Len(str); i++) {
		buf[position++] = Asc(Mid(str, i, 1));
	}

	return position - was;
}

function int readVarInt() {
	local int multiplier, value;
	local byte encodedByte;

	if (!hasRemaining(1)) return -1;

	multiplier = 1;
	value = 0;

	do {
		encodedByte = buf[position++];
		value += (encodedByte & 127) * multiplier;
		if (multiplier > 128*128*128) {
			warn("Malformed Variable Byte value at position " $ position);
			return -1;
		}
		multiplier *= 128;
	} until (!((encodedByte & 128) != 0))

	return value;
}

function int writeVarInt(int value) {
	local byte encodedByte, rem;
	local int was;

	if (value > 268435455) {
		warn("Cannot encode size larger than 268435455, got " $ value);
		return -1;
	}

	if (!hasCapacity(1)) return -1;
	was = position;

	rem = value;
	do {
		encodedByte = rem % 128;
		rem = rem / 128;
		if (rem > 0) encodedByte = encodedByte | 128;
		buf[position++] = encodedByte;
	} until (!(rem > 0))

	return position - was;
}


function private bool hasRemaining(int neededBytes) {
	if (remaining < neededBytes) {
		warn("Requested bytes " $ neededBytes $ ", but only have " $ remaining);
		return false;
	}
	return true;
}

function private bool hasCapacity(int wantedSpace) {
	if (wantedSpace > (CAPACITY - position)) {
		warn("Need space for bytes " $ wantedSpace $ ", but only have " $ (CAPACITY - position));
		return false;
	}
	return true;
}

defaultproperties {
}
