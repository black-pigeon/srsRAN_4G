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
    profile_args=(--enb.n_prb=25 --rf.srate=5760000 --rf.time_adv_nsamples=0
      --enb_files.sib_config="$SCRIPT_DIR/sib_25prb.conf"
      --rf.device_args="type=ant,addr=192.168.1.10,product=E200,recv_frame_size=1472,recv_buff_size=33554432,rx_subdev_spec=A:A,tx_subdev_spec=A:A,send_frame_size=1472,send_buff_size=33554432,num_recv_frames=2048,num_send_frames=2048,ignore_tx_timestamps=false,master_clock_rate=23.04e6,sampling_rate=5.76e6") ;;
  6prb)
    profile_args=(--enb.n_prb=6 --rf.srate=1920000 --rf.time_adv_nsamples=49
      --enb_files.sib_config="$SCRIPT_DIR/sib_6prb.conf"
      --rf.device_args="type=ant,addr=192.168.1.10,product=E200,recv_frame_size=1472,recv_buff_size=33554432,rx_subdev_spec=A:A,tx_subdev_spec=A:A,send_frame_size=1472,send_buff_size=1472,num_recv_frames=2048,num_send_frames=2048,ignore_tx_timestamps=false,master_clock_rate=23.04e6,sampling_rate=1.92e6") ;;
  15prb)
    profile_args=(--enb.n_prb=15 --rf.srate=3840000 --rf.time_adv_nsamples=25
      --enb_files.sib_config="$SCRIPT_DIR/sib_25prb.conf"
      --rf.device_args="type=ant,addr=192.168.1.10,product=E200,recv_frame_size=1472,recv_buff_size=33554432,rx_subdev_spec=A:A,tx_subdev_spec=A:A,send_frame_size=1472,send_buff_size=33554432,num_recv_frames=2048,num_send_frames=2048,ignore_tx_timestamps=false,master_clock_rate=23.04e6,sampling_rate=3.84e6") ;;
  *) echo "Unknown profile '$profile' (use 6prb, 15prb, or 25prb)" >&2; exit 2 ;;
esac

echo "Using ANTSDR eNB profile: $profile"
exec sudo -E env LD_LIBRARY_PATH="$LD_LIBRARY_PATH" UHD_IMAGES_DIR="$UHD_IMAGES_DIR" \
  "$SRSRAN_LOCAL_BIN/srsenb/src/srsenb" "$SCRIPT_DIR/enb.conf" "${profile_args[@]}" "$@"
