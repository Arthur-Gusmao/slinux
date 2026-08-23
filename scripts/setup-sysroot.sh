#!/bin/sh
# setup-sysroot.sh - create musl sysroot with headers and libraries
# Usage: setup-sysroot.sh <sysroot_dir>

set -eu

SYSROOT="$1"
SRC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Setting up sysroot at $SYSROOT"

# The musl build will populate this, but we need the directory structure early
mkdir -p "$SYSROOT"/{bin,lib,include,usr/bin,usr/lib,usr/include}

# The actual musl build will install into this sysroot
# We just need the directory to exist for the build system
touch "$SYSROOT/.stamp"