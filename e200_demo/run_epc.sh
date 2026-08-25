#!/usr/bin/env bash
set -euo pipefail

demo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "${demo_dir}/.." && pwd)
rf_lib_dir="${project_dir}/build/lib/src/phy/rf"
epc_bin="${project_dir}/build/srsepc/src/srsepc"

if [[ ! -x "${epc_bin}" ]]; then
  echo "Missing ${epc_bin}; build the project first." >&2
  exit 1
fi
if (( EUID != 0 )); then
  echo "srsEPC needs root/CAP_NET_ADMIN to create srs_spgw_sgi." >&2
  echo "Run: sudo ${demo_dir}/run_epc.sh" >&2
  exit 1
fi

export LD_LIBRARY_PATH="${rf_lib_dir}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
cd -- "${demo_dir}"
exec "${epc_bin}" "${demo_dir}/epc.conf" "$@"
