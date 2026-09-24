#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=env.sh
source "$SCRIPT_DIR/env.sh"
exec sudo -E env LD_LIBRARY_PATH="$LD_LIBRARY_PATH" UHD_IMAGES_DIR="$UHD_IMAGES_DIR" \
  "$SRSRAN_LOCAL_BIN/srsepc/src/srsepc" "$SCRIPT_DIR/epc.conf"
