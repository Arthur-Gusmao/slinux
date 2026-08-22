/* minimal libbsd shim for openrdate on musl: u_char etc. come from
 * sys/types.h and arc4random(3) is implemented over getrandom(2),
 * which this musl does not yet provide. */
#include <stdlib.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/random.h>

static inline uint32_t arc4random(void)
{
	uint32_t v;
	ssize_t r;

	do
		r = getrandom(&v, sizeof v, 0);
	while (r != (ssize_t)sizeof v);

	return v;
}
