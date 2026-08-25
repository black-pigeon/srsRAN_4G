#!/usr/bin/env bash

# This file is sourced by run_enb.sh and run_ue.sh.
load_e200_profile()
{
  local demo_dir=$1
  local profile_name=$2
  local profile_file

  if [[ ! ${profile_name} =~ ^(6|15|25|50|75|100)prb$ &&
        ! ${profile_name} =~ ^e206_enb_(15|25|50)prb$ &&
        ! ${profile_name} =~ ^e200_enb_e100_ue_(15|25|50|75)prb$ &&
        ! ${profile_name} =~ ^e100_enb_e200_ue_(6|15|25|50|75)prb$ &&
        ${profile_name} != e100_enb_e200_ue_6prb_external &&
        ${profile_name} != e200_enb_e100_ue_6prb &&
        ${profile_name} != 6prb_adv66 && ${profile_name} != 6prb_external ]]; then
    echo "Invalid E200 profile '${profile_name}'." >&2
    echo "Available profiles: 6prb 6prb_external 6prb_adv66 15prb 25prb 50prb 75prb 100prb e100_enb_e200_ue_6prb e100_enb_e200_ue_6prb_external e100_enb_e200_ue_15prb e100_enb_e200_ue_25prb e100_enb_e200_ue_50prb e100_enb_e200_ue_75prb e200_enb_e100_ue_6prb e200_enb_e100_ue_15prb e200_enb_e100_ue_25prb e200_enb_e100_ue_50prb e200_enb_e100_ue_75prb e206_enb_15prb e206_enb_25prb e206_enb_50prb" >&2
    return 1
  fi

  profile_file="${demo_dir}/profiles/${profile_name}.conf"
  if [[ ! -r ${profile_file} ]]; then
    echo "Missing E200 profile: ${profile_file}" >&2
    return 1
  fi

  unset E200_N_PRB E200_TIME_ADV_NSAMPLES E200_CLOCK_SOURCE E200_UE_NETNS E200_SIB_CONFIG
  unset E200_ENB_ADDR E200_UE_ADDR E200_ENB_SAMPLE_RATE E200_UE_SAMPLE_RATE
  unset E200_ENB_TIME_ADV_NSAMPLES
  unset E200_ENB_RX_GAIN E200_UE_TX_GAIN E200_UE_FORCE_UL_AMPLITUDE
  # The profile files are repository-owned shell assignments.
  # shellcheck source=/dev/null
  source "${profile_file}"

  if [[ ! ${E200_N_PRB:-} =~ ^(6|15|25|50|75|100)$ ]]; then
    echo "Invalid E200_N_PRB in ${profile_file}" >&2
    return 1
  fi
  if [[ ! ${E200_TIME_ADV_NSAMPLES:-} =~ ^-?[0-9]+$ ]]; then
    echo "Invalid E200_TIME_ADV_NSAMPLES in ${profile_file}" >&2
    return 1
  fi
  if [[ ${E200_CLOCK_SOURCE:-} != internal && ${E200_CLOCK_SOURCE:-} != external ]]; then
    echo "Invalid E200_CLOCK_SOURCE in ${profile_file}" >&2
    return 1
  fi
  if [[ -n ${E200_UE_NETNS:-} && ! ${E200_UE_NETNS} =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    echo "Invalid E200_UE_NETNS in ${profile_file}" >&2
    return 1
  fi
  if [[ -n ${E200_SIB_CONFIG:-} && ! -r ${demo_dir}/${E200_SIB_CONFIG} ]]; then
    echo "Missing E200_SIB_CONFIG from ${profile_file}: ${demo_dir}/${E200_SIB_CONFIG}" >&2
    return 1
  fi
  E200_ENB_ADDR=${E200_ENB_ADDR:-192.168.1.10}
  E200_UE_ADDR=${E200_UE_ADDR:-192.168.10.2}
  E200_ENB_TIME_ADV_NSAMPLES=${E200_ENB_TIME_ADV_NSAMPLES:-0}
  if [[ ! ${E200_ENB_ADDR} =~ ^[0-9]+(\.[0-9]+){3}$ ||
        ! ${E200_UE_ADDR} =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    echo "Invalid E200_ENB_ADDR/E200_UE_ADDR in ${profile_file}" >&2
    return 1
  fi
  if [[ -n ${E200_ENB_SAMPLE_RATE:-} && ! ${E200_ENB_SAMPLE_RATE} =~ ^[0-9]+$ ]]; then
    echo "Invalid E200_ENB_SAMPLE_RATE in ${profile_file}" >&2
    return 1
  fi
  if [[ -n ${E200_UE_SAMPLE_RATE:-} && ! ${E200_UE_SAMPLE_RATE} =~ ^[0-9]+$ ]]; then
    echo "Invalid E200_UE_SAMPLE_RATE in ${profile_file}" >&2
    return 1
  fi
  if [[ ! ${E200_ENB_TIME_ADV_NSAMPLES} =~ ^-?[0-9]+$ ]]; then
    echo "Invalid E200_ENB_TIME_ADV_NSAMPLES in ${profile_file}" >&2
    return 1
  fi
  if [[ -n ${E200_ENB_RX_GAIN:-} && ! ${E200_ENB_RX_GAIN} =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Invalid E200_ENB_RX_GAIN in ${profile_file}" >&2
    return 1
  fi
  if [[ -n ${E200_UE_TX_GAIN:-} && ! ${E200_UE_TX_GAIN} =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Invalid E200_UE_TX_GAIN in ${profile_file}" >&2
    return 1
  fi
  if [[ -n ${E200_UE_FORCE_UL_AMPLITUDE:-} &&
        ! ${E200_UE_FORCE_UL_AMPLITUDE} =~ ^(0([.][0-9]+)?|1([.]0+)?)$ ]]; then
    echo "Invalid E200_UE_FORCE_UL_AMPLITUDE in ${profile_file}" >&2
    return 1
  fi

  E200_PROFILE_NAME=${profile_name}
  E200_PROFILE_FILE=${profile_file}
  export E200_PROFILE_NAME E200_PROFILE_FILE
  export E200_N_PRB E200_TIME_ADV_NSAMPLES E200_CLOCK_SOURCE E200_UE_NETNS E200_SIB_CONFIG
  export E200_ENB_ADDR E200_UE_ADDR E200_ENB_SAMPLE_RATE E200_UE_SAMPLE_RATE
  export E200_ENB_TIME_ADV_NSAMPLES
  export E200_ENB_RX_GAIN E200_UE_TX_GAIN E200_UE_FORCE_UL_AMPLITUDE
}
