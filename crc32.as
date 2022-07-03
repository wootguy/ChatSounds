array<uint32> crc32_table(256);

void crc32_init()
{
	uint32 polynomial = 0xEDB88320;
	for (uint32 i = 0; i < 256; i++)
	{
		uint32 c = i;
		for (int j = 0; j < 8; j++)
		{
			if (c & 1 != 0) {
				c = polynomial ^ (c >> 1);
			}
			else {
				c >>= 1;
			}
		}
		crc32_table[i] = c;
	}
}

uint32 crc32_get(array<uint8>@ buf, uint len)
{
	uint32 c = 0xFFFFFFFF;
	for (size_t i = 0; i < len; ++i)
	{
		c = crc32_table[(c ^ buf[i]) & 0xFF] ^ (c >> 8);
	}
	return c ^ 0xFFFFFFFF;
}