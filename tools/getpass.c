/* getpass - read a line with echo disabled; prompt goes to stderr,
 * the line (newline stripped) to stdout so callers can use $(...) */
#include <stdio.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

static char buf[512];

int main(int argc, char **argv)
{
	struct termios oldt, newt;
	ssize_t n;
	size_t len;
	int echo_off = 0;

	if (argc != 2) {
		fprintf(stderr, "usage: getpass prompt\n");
		return 2;
	}
	fprintf(stderr, "%s ", argv[1]);
	fflush(stderr);
	/* no tty (pipe/file): fall back to an ordinary echoing read */
	if (tcgetattr(STDIN_FILENO, &oldt) == 0) {
		newt = oldt;
		newt.c_lflag &= ~(tcflag_t)ECHO;
		if (tcsetattr(STDIN_FILENO, TCSANOW, &newt) != 0)
			return 1;
		echo_off = 1;
	}
	n = read(STDIN_FILENO, buf, sizeof(buf) - 1);
	if (echo_off)
		tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
	fputc('\n', stderr);
	if (n <= 0)
		return 1;
	len = (size_t)n;
	while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r'))
		buf[--len] = '\0';
	fwrite(buf, 1, len, stdout);
	fputc('\n', stdout);
	return 0;
}
