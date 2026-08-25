#!/usr/bin/env bash
set -euo pipefail

demo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "${demo_dir}/.." && pwd)
rf_lib_dir="${project_dir}/build/lib/src/phy/rf"
profile_name=""

if [[ ${1:-} == --profile ]]; then
  [[ $# -ge 2 ]] || { echo "--profile requires a value." >&2; exit 1; }
  profile_name=$2
  shift 2
elif [[ ${1:-} == --profile=* ]]; then
  profile_name=${1#--profile=}
  shift
fi
if (( $# != 0 )); then
  echo "Usage: $0 [--profile PROFILE]" >&2
  exit 1
fi

export LD_LIBRARY_PATH="${rf_lib_dir}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

for executable in \
  "${project_dir}/build/srsepc/src/srsepc" \
  "${project_dir}/build/srsenb/src/srsenb" \
  "${project_dir}/build/srsue/src/srsue" \
  "${rf_lib_dir}/libsrsran_rf_uhd.so"; do
  [[ -e "${executable}" ]] || { echo "Missing: ${executable}" >&2; exit 1; }
done

addresses=(192.168.1.10 192.168.10.2)
clock_source=internal
if [[ -n ${profile_name} ]]; then
  # shellcheck source=load_profile.sh
  source "${demo_dir}/load_profile.sh"
  load_e200_profile "${demo_dir}" "${profile_name}"
  addresses=("${E200_ENB_ADDR}" "${E200_UE_ADDR}")
  clock_source=${E200_CLOCK_SOURCE}
  echo "Using ${E200_PROFILE_NAME}: PRB=${E200_N_PRB}, eNB=${E200_ENB_ADDR}, UE=${E200_UE_ADDR}, clock=${clock_source}"
fi

for address in "${addresses[@]}"; do
  echo "Checking SDR ${address}..."
  ping -c 1 -W 1 "${address}" >/dev/null
  timeout 20s uhd_usrp_probe --args="addr=${address},clock_source=${clock_source}" 2>&1 |
    grep -E 'Detected Device|Mboard:|serial:'
  if [[ ${clock_source} == external ]]; then
    echo "Checking external reference lock on ${address}..."
    timeout 20s uhd_usrp_probe \
      --args="addr=${address},clock_source=external" \
      --sensor /mboards/0/sensors/ref_locked 2>&1 | tail -n 1 | grep -Fx true
  fi
done

benchmark_rate=/usr/local/lib/uhd/examples/benchmark_rate
if [[ -x "${benchmark_rate}" ]]; then
  for address in "${addresses[@]}"; do
    echo "Testing receive-only 1.92 MSps on ${address}..."
    benchmark_output=$(timeout 15s "${benchmark_rate}" \
      --args="addr=${address},clock_source=${clock_source}" \
      --rx_rate=1.92e6 --rx_channels=0 --duration=2 2>&1)
    grep -E 'Actually got clock rate 1.920000 MHz|Num received samples:|Num dropped samples:|Num overruns detected:|Num timeouts \(Rx\):' \
      <<<"${benchmark_output}"
    grep -Eq 'Num dropped samples:[[:space:]]+0$' <<<"${benchmark_output}"
    grep -Eq 'Num overruns detected:[[:space:]]+0$' <<<"${benchmark_output}"
    grep -Eq 'Num timeouts \(Rx\):[[:space:]]+0$' <<<"${benchmark_output}"
  done
fi

loaded_rf=$(ldd "${project_dir}/build/srsenb/src/srsenb" | awk '/libsrsran_rf.so/{print $3}')
case "${loaded_rf}" in
  "${rf_lib_dir}"/*) ;;
  *) echo "Wrong RF library selected: ${loaded_rf}" >&2; exit 1 ;;
esac

echo "Build, RF plugin selection, routing, reference clock, and both SDR RX paths are OK."
