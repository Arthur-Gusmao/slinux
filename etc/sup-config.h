// sup's configuration file for slinux
// need sup to be re-compiled for any change to be effective

#define HASH 1
#define DAEMON 1

#ifndef FLAGSONLY

#define USER 1000
#define GROUP -1

#define SETUID 0
#define SETGID 0

#define CHROOT ""
#define CHRDIR ""

// rules apply to uid 0 (root) only; add entries for unprivileged
// users here, e.g. to let uid 1000 run halt(8) and ifconfig(8):
//
// { USER, -1, "halt",     "/bin/halt",     "" },
// { USER, -1, "ifconfig", "/bin/ifconfig", "" },
static struct rule_t rules[] = {
    { 0, GROUP, "whoami", "/bin/whoami", "" },
    { USER, GROUP, "whoami", "/bin/whoami", "" },
    { 0 },
};

#endif
