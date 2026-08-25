#!/usr/bin/env bash
set -euo pipefail

demo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "${demo_dir}/.." && pwd)
rf_lib_dir="${project_dir}/build/lib/src/phy/rf"
ue_bin="${project_dir}/build/srsue/src/srsue"
profile_name=${E200_PROFILE:-}

if [[ ${1:-} == --profile ]]; then
  [[ $# -ge 2 ]] || { echo "--profile requires a value." >&2; exit 1; }
  profile_name=$2
  shift 2
elif [[ ${1:-} == --profile=* ]]; then
  profile_name=${1#--profile=}
  shift
fi

if [[ ! -x "${ue_bin}" ]]; then
  echo "Missing ${ue_bin}; build the project first." >&2
  exit 1
fi
if (( EUID != 0 )); then
  echo "srsUE needs root/CAP_NET_ADMIN to create tun_srsue." >&2
  echo "Run: sudo ${demo_dir}/run_ue.sh" >&2
  exit 1
fi
export LD_LIBRARY_PATH="${rf_lib_dir}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
cd -- "${demo_dir}"

profile_args=()
ue_addr=192.168.10.2
if [[ -n ${profile_name} ]]; then
  # shellcheck source=load_profile.sh
  source "${demo_dir}/load_profile.sh"
  load_e200_profile "${demo_dir}" "${profile_name}"
  ue_addr=${E200_UE_ADDR}
  if [[ -n ${E200_UE_NETNS} ]] && ! ip netns list | awk '{print $1}' | grep -Fxq "${E200_UE_NETNS}"; then
    ip netns add "${E200_UE_NETNS}"
  fi
  profile_args+=(
    "--rf.time_adv_nsamples=${E200_TIME_ADV_NSAMPLES}"
    "--rf.device_args=addr=${ue_addr},recv_frame_size=1472,send_frame_size=1472,ignore_tx_timestamps=false,clock=${E200_CLOCK_SOURCE},clock_source=${E200_CLOCK_SOURCE}"
  )
  if [[ -n ${E200_UE_SAMPLE_RATE:-} ]]; then
    profile_args+=("--rf.srate=${E200_UE_SAMPLE_RATE}")
  fi
  if [[ -n ${E200_UE_TX_GAIN:-} ]]; then
    profile_args+=("--rf.tx_gain=${E200_UE_TX_GAIN}")
  fi
  if [[ -n ${E200_UE_FORCE_UL_AMPLITUDE:-} ]]; then
    profile_args+=("--phy.force_ul_amplitude=${E200_UE_FORCE_UL_AMPLITUDE}")
  fi
  if [[ -n ${E200_UE_NETNS} ]]; then
    profile_args+=("--gw.netns=${E200_UE_NETNS}")
  fi
  echo "Using ${E200_PROFILE_NAME}: PRB=${E200_N_PRB}, srate=${E200_UE_SAMPLE_RATE:-native}, time_adv=${E200_TIME_ADV_NSAMPLES}, tx_gain=${E200_UE_TX_GAIN:-config}, ul_amplitude=${E200_UE_FORCE_UL_AMPLITUDE:-auto}, addr=${ue_addr}, clock=${E200_CLOCK_SOURCE}, netns=${E200_UE_NETNS:-default}"
fi

if ! ping -c 1 -W 1 "${ue_addr}" >/dev/null; then
  echo "UE SDR at ${ue_addr} is unreachable." >&2
  exit 1
fi

exec "${ue_bin}" "${demo_dir}/ue.conf" "${profile_args[@]}" "$@"
