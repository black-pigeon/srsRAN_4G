#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=env.sh
source "$SCRIPT_DIR/env.sh"

profile=${ANTSDR_PROFILE:-25prb}
if [[ ${1:-} == --profile ]]; then
  [[ $# -ge 2 ]] || { echo "--profile requires 6prb, 15prb, or 25prb" >&2; exit 2; }
  profile=$2; shift 2
elif [[ ${1:-} == --profile=* ]]; then
  profile=${1#--profile=}; shift
fi

case "$profile" in
  25prb)
    profile_args=(--rf.srate=5760000 --rf.time_adv_nsamples=100
      --rf.device_args="type=ant,addr=192.168.10.122,product=E310v2,recv_frame_size=1472,recv_buff_size=33554432,rx_subdev_spec=A:A,tx_subdev_spec=A:A,send_frame_size=1472,send_buff_size=33554432,num_recv_frames=2048,num_send_frames=2048,ignore_tx_timestamps=false,master_clock_rate=23.04e6,sampling_rate=5.76e6") ;;
  6prb)
    profile_args=(--rf.srate=1920000 --rf.time_adv_nsamples=67
      --rf.device_args="type=ant,addr=192.168.10.122,product=E310v2,recv_frame_size=1472,recv_buff_size=33554432,rx_subdev_spec=A:A,tx_subdev_spec=A:A,send_frame_size=1472,send_buff_size=1472,num_recv_frames=2048,num_send_frames=2048,ignore_tx_timestamps=false,master_clock_rate=23.04e6,sampling_rate=1.92e6") ;;
  15prb)
    profile_args=(--rf.srate=3840000 --rf.time_adv_nsamples=83
      --rf.device_args="type=ant,addr=192.168.10.122,product=E310v2,recv_frame_size=1472,recv_buff_size=33554432,rx_subdev_spec=A:A,tx_subdev_spec=A:A,send_frame_size=1472,send_buff_size=33554432,num_recv_frames=2048,num_send_frames=2048,ignore_tx_timestamps=false,master_clock_rate=23.04e6,sampling_rate=3.84e6") ;;
  *) echo "Unknown profile '$profile' (use 6prb, 15prb, or 25prb)" >&2; exit 2 ;;
esac

# Keep the UE gateway in its own network namespace.  When EPC and srsUE run on
# the same host, the host's local route to 172.16.0.1 can otherwise bypass the
# LTE bearer and make an apparently attached UE fail the data-plane test.
UE_NETNS=${SRSUE_NETNS:-ue1}
if ! ip netns list | awk '{print $1}' | grep -Fxq "$UE_NETNS"; then
  sudo ip netns add "$UE_NETNS"
fi

exec sudo -E env LD_LIBRARY_PATH="$LD_LIBRARY_PATH" UHD_IMAGES_DIR="$UHD_IMAGES_DIR" \
  "$SRSRAN_LOCAL_BIN/srsue/src/srsue" "$SCRIPT_DIR/ue.conf" "${profile_args[@]}" \
  --gw.netns="$UE_NETNS" "$@"
