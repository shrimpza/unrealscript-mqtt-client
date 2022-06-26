class ByteBuffer extends Object;

const CAPACITY = 1024;

var private byte buf[CAPACITY];
var private int limit, position, marker;

/**
 * Resets the current position to the beginning, and sets the limit
 * to the capacity. The marker is also reset.
 *
 * Any data in the buffer is not changed, since subsequent write
 * operations will overwrite it.
 */
function clear() {
	position = 0;
	limit = CAPACITY;
	marker = 0;
}

/**
 * Sets the limit to the current position, then sets the position to
 * the beginning. The marker is also reset.
 *
 * This us useful after a series of write operations, where data has
 * been written, flipping the buffer then sets the limit tot he data
 * size, and puts the position at the beginning, allowing subsequent
 * read operations on the data.
 */
function flip() {
	limit = position;
	position = 0;
	marker = 0;
}

/**
 * Move all data between the current position and the limit to the
 * beginning, and set the position to the beginning. The limit is
 * set to the capacity.
 */
function compact() {
  local int i, n;
  if (position == 0) return;

  n = 0;
  for (i = position; i < limit; i++) {
  	buf[n++] = buf[i];
  }

	limit = CAPACITY;
  position = 0;
}

/**
 * Set the market to the current position. Move to the marked
 * position by calling reset().
 */
function mark() {
	marker = position;
}

/**
 * Sets the position to a previously marked position.
 */
function reset() {
	position = marker;
}

/**
 * Returns true if the position is before the limit.
 */
function bool hasRemaining() {
	return position < limit;
}

/**
 * Returns the amount of space remaining in the buffer, between
 * the current position and the limit.
 */
function int remaining() {
	return limit - position;
}

/**
 * Returns the current position
 */
function int getPosition() {
	return position;
}

/**
 * Sets the position to the new position specified, if less than
 * the limit. Returns false if the position was not changed.
 *
 * If the marker is greater than the new position, it is reset.
 */
function bool setPosition(int newPosition) {
	if (position < limit) {
		position = newPosition;
		if (marker > position) marker = 0;
		return true;
	}
	return false;
}

/**
 * Write bytes to the buffer, at the current position, returning
 * the number of bytes written.
 *
 * The from and to parameters allow writing a subset of the data.
 */
function int putBytes(byte data[255], int from, int count) {
	local int was, i;

	if (from + count > 255) {
		warn("Invalid range for from [" $ from $ "] and count [" $ count $ "]");
		return -1;
	}

	if (!canWrite(count)) {
		return -1;
	}

	was = position;
	for (i = from; i < from + count && position < limit; i++) {
		buf[position++] = data[i];
	}

	return position - was;
}

/**
 * Read a single byte from the current position, and advance by 1.
 */
function byte get() {
	if (!canRead(1)) return -1;
	return buf[position++];
}

/**
 * Write a single byte from the current position, and advance by 1.
 */
function int put(byte val) {
	local int was;
	if (!canWrite(1)) return -1;
	was = position;

	buf[position++] = val;

	return position - was;
}

function int getShort() {
	if (!canRead(2)) return -1;
	return buf[position++] << 8 | buf[position++];
}

function int putShort(int val) {
	local int was;
	if (!canWrite(2)) return -1;
	was = position;

	buf[position++] = ((val >> 8) & 0xff);
	buf[position++] = val & 0xff;

	return position - was;
}

// TODO readInt

function int putInt(int val) {
	local int was;
	if (!canWrite(4)) return -1;
	was = position;

	buf[position++] = (val & 0xff000000) >> 24;
	buf[position++] = (val & 0x00ff0000) >> 16;
	buf[position++] = (val & 0x0000ff00) >> 8;
	buf[position++] =  val & 0x000000ff;

	return position - was;
}

// FIXME doc to note short prefix
function String getString() {
	local int len, i;
	local String str;
	if (!canRead(2)) return "";
	len = getShort();

	if (len == -1) return "";

	if (!canRead(len)) {
		position =- 2; // rewind, so we can try again? hax?!
		return "";
	}

	for (i = 0; i < len; i++) {
		str = str $ Chr(buf[position++]);
	}

	return str;
}

// FIXME doc to note short prefix
function int putString(String str) {
	local int i, was;
	if (!canWrite(2 + Len(str))) return -1;
	was = position;

	putShort(Len(str));
	for (i = 0; i < Len(str); i++) {
		buf[position++] = Asc(Mid(str, i, 1));
	}

	return position - was;
}

function int getVarInt() {
	local int multiplier, value;
	local byte encodedByte;

	if (!canRead(1)) return -1;

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

function int putVarInt(int value) {
	local byte encodedByte, rem;
	local int was;

	if (value > 268435455) {
		warn("Cannot encode size larger than 268435455, got " $ value);
		return -1;
	}

	if (!canWrite(1)) return -1;
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

function private bool canRead(int neededBytes) {
	if (remaining() < neededBytes) {
		warn("Requested bytes " $ neededBytes $ ", but only have " $ remaining());
		return false;
	}
	return true;
}

function private bool canWrite(int wantedSpace) {
	if (wantedSpace > (limit - position)) {
		warn("Need space for bytes " $ wantedSpace $ ", but only have " $ (CAPACITY - position));
		return false;
	}
	return true;
}

defaultproperties {
}
