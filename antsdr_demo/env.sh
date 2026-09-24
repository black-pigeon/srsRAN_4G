#!/usr/bin/env bash
# Runtime environment for the private ANTSDR UHD 4.1 installation.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
export ANTSDR_UHD_PREFIX=${ANTSDR_UHD_PREFIX:-/opt/antsdr-uhd}
export SRSRAN_PREFIX=${SRSRAN_PREFIX:-/home/wcc/.local/srsran-antsdr}
export PATH="$ANTSDR_UHD_PREFIX/bin:$SRSRAN_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$ANTSDR_UHD_PREFIX/lib:$SRSRAN_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export UHD_IMAGES_DIR="$ANTSDR_UHD_PREFIX/share/uhd/images"
export SRSRAN_LOCAL_ROOT="$REPO_DIR"
export SRSRAN_LOCAL_BIN="$REPO_DIR/build-antsdr-local"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  exec "$@"
fi
