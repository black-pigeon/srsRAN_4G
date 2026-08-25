#!/usr/bin/env bash
set -euo pipefail

demo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "${demo_dir}/.." && pwd)
rf_lib_dir="${project_dir}/build/lib/src/phy/rf"
enb_bin="${project_dir}/build/srsenb/src/srsenb"
profile_name=${E200_PROFILE:-}

if [[ ${1:-} == --profile ]]; then
  [[ $# -ge 2 ]] || { echo "--profile requires a value." >&2; exit 1; }
  profile_name=$2
  shift 2
elif [[ ${1:-} == --profile=* ]]; then
  profile_name=${1#--profile=}
  shift
fi

if [[ ! -x "${enb_bin}" ]]; then
  echo "Missing ${enb_bin}; build the project first." >&2
  exit 1
fi
if (( EUID != 0 )); then
  echo "Run srsENB as root so its radio threads can use real-time priority." >&2
  echo "Run: sudo ${demo_dir}/run_enb.sh" >&2
  exit 1
fi
export LD_LIBRARY_PATH="${rf_lib_dir}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
cd -- "${demo_dir}"

profile_args=()
enb_addr=192.168.1.10
if [[ -n ${profile_name} ]]; then
  # shellcheck source=load_profile.sh
  source "${demo_dir}/load_profile.sh"
  load_e200_profile "${demo_dir}" "${profile_name}"
  enb_addr=${E200_ENB_ADDR}
  profile_args+=(
    "--enb.n_prb=${E200_N_PRB}"
    "--rf.time_adv_nsamples=${E200_ENB_TIME_ADV_NSAMPLES}"
    "--rf.device_args=addr=${enb_addr},recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=${E200_CLOCK_SOURCE},clock_source=${E200_CLOCK_SOURCE}"
  )
  if [[ -n ${E200_ENB_SAMPLE_RATE:-} ]]; then
    profile_args+=("--rf.srate=${E200_ENB_SAMPLE_RATE}")
  fi
  if [[ -n ${E200_ENB_RX_GAIN:-} ]]; then
    profile_args+=("--rf.rx_gain=${E200_ENB_RX_GAIN}")
  fi
  if [[ -n ${E200_SIB_CONFIG:-} ]]; then
    profile_args+=("--enb_files.sib_config=${demo_dir}/${E200_SIB_CONFIG}")
  fi
  echo "Using ${E200_PROFILE_NAME}: PRB=${E200_N_PRB}, srate=${E200_ENB_SAMPLE_RATE:-native}, time_adv=${E200_ENB_TIME_ADV_NSAMPLES}, rx_gain=${E200_ENB_RX_GAIN:-config}, addr=${enb_addr}, clock=${E200_CLOCK_SOURCE}"
fi

if ! ping -c 1 -W 1 "${enb_addr}" >/dev/null; then
  echo "eNB SDR at ${enb_addr} is unreachable." >&2
  exit 1
fi

exec "${enb_bin}" "${demo_dir}/enb.conf" "${profile_args[@]}" "$@"
