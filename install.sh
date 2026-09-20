#!/usr/bin/env bash
# Compatibility entry point; the destructive workflow lives under installer/.
set -Eeuo pipefail
exec bash "$(dirname -- "${BASH_SOURCE[0]}")/installer/install.sh" "$@"
