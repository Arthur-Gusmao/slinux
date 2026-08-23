/* cryptpw - print a sha512-crypt hash of the given password */
#define _GNU_SOURCE
#include <crypt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	static const char cs[] =
		"./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		"abcdefghijklmnopqrstuvwxyz";
	char salt[20];
	unsigned seed;
	int i;

	if (argc != 2) {
		fprintf(stderr, "usage: cryptpw password\n");
		return 2;
	}
	memcpy(salt, "$6$", 3);
	seed = (unsigned)time(NULL) ^ ((unsigned)getpid() << 16);
	for (i = 0; i < 16; i++) {
		seed = seed * 1103515245u + 12345u;
		salt[3 + i] = cs[(seed >> 16) & 63];
	}
	salt[19] = '\0';
	puts(crypt(argv[1], salt));
	return 0;
}
