#include <uhd/stream.hpp>
#include <uhd/types/stream_cmd.hpp>
#include <uhd/usrp/multi_usrp.hpp>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr double kRate = 5.76e6;
constexpr double kFrequency = 2680e6;

struct power_record {
  uint64_t tick;
  double power;
  size_t samples;
};

struct async_record {
  uhd::async_metadata_t::event_code_t code;
  bool has_time;
  uint64_t tick;
};

} // namespace

int main(int argc, char** argv)
{
  const std::string tx_address = argc > 1 ? argv[1] : "192.168.1.10";
  const std::string rx_address = argc > 2 ? argv[2] : "192.168.10.2";
  const std::string mode = argc > 3 ? argv[3] : "strict";
  const bool strict = mode != "asap";
  const bool force_late = mode == "late";
  const size_t requested_samples = argc > 4 ? std::stoull(argv[4]) : 0;
  const double tx_gain = argc > 5 ? std::stod(argv[5]) : 30.0;
  const double rate = argc > 6 ? std::stod(argv[6]) : kRate;
  const std::string clock_source = argc > 7 ? argv[7] : "external";
  const std::string common = ",recv_frame_size=1472,send_frame_size=1472";

  try {
    auto tx_usrp = uhd::usrp::multi_usrp::make(
        "addr=" + tx_address + common +
        ",ignore_tx_timestamps=" + (strict ? "false" : "true"));
    auto rx_usrp = uhd::usrp::multi_usrp::make("addr=" + rx_address + common);

    tx_usrp->set_clock_source(clock_source);
    rx_usrp->set_clock_source(clock_source);
    tx_usrp->set_tx_rate(rate, 0);
    rx_usrp->set_rx_rate(rate, 0);
    tx_usrp->set_tx_freq(kFrequency, 0);
    rx_usrp->set_rx_freq(kFrequency, 0);
    tx_usrp->set_tx_gain(tx_gain, 0);
    rx_usrp->set_rx_gain(40.0, 0);
    tx_usrp->set_tx_bandwidth(5e6, 0);
    rx_usrp->set_rx_bandwidth(5e6, 0);
    tx_usrp->set_time_now(uhd::time_spec_t(0.0));
    rx_usrp->set_time_now(uhd::time_spec_t(0.0));

    uhd::stream_args_t stream_args("fc32", "sc16");
    stream_args.channels = {0};
    auto rx = rx_usrp->get_rx_stream(stream_args);
    auto tx = tx_usrp->get_tx_stream(stream_args);

    std::vector<power_record> records;
    std::atomic<bool> rx_started{false};
    std::thread receiver([&]() {
      uhd::stream_cmd_t command(uhd::stream_cmd_t::STREAM_MODE_START_CONTINUOUS);
      command.stream_now = true;
      rx->issue_stream_cmd(command);
      rx_started = true;

      std::vector<std::complex<float>> samples(rx->get_max_num_samps());
      const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(450);
      while (std::chrono::steady_clock::now() < deadline) {
        uhd::rx_metadata_t metadata;
        const size_t count = rx->recv(samples.data(), samples.size(), metadata, 0.1, true);
        if (count == 0 || metadata.error_code != uhd::rx_metadata_t::ERROR_CODE_NONE) {
          continue;
        }
        double power = 0.0;
        for (size_t i = 0; i < count; ++i) {
          power += std::norm(samples[i]);
        }
        records.push_back({metadata.time_spec.to_ticks(rate), power / count, count});
      }

      command.stream_mode = uhd::stream_cmd_t::STREAM_MODE_STOP_CONTINUOUS;
      rx->issue_stream_cmd(command);
    });

    while (!rx_started.load()) {
      std::this_thread::yield();
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));

    const size_t burst_samples = requested_samples != 0
                                     ? requested_samples
                                     : static_cast<size_t>(rate * 0.020);
    std::vector<std::complex<float>> burst(burst_samples);
    for (size_t i = 0; i < burst.size(); ++i) {
      const double phase = 2.0 * M_PI * 200e3 * static_cast<double>(i) / rate;
      burst[i] = std::polar(0.7f, static_cast<float>(phase));
    }

    const auto before_send = tx_usrp->get_time_now();
    uhd::tx_metadata_t metadata;
    metadata.start_of_burst = true;
    metadata.end_of_burst = true;
    metadata.has_time_spec = strict;
    metadata.time_spec = before_send + uhd::time_spec_t(force_late ? -0.001 : 0.005);
    const size_t sent = tx->send(burst.data(), burst.size(), metadata, 1.0);
    const auto after_send = tx_usrp->get_time_now();

    std::vector<async_record> async_events;
    uhd::async_metadata_t async_metadata;
    while (tx->recv_async_msg(async_metadata, 0.05)) {
      async_events.push_back({async_metadata.event_code,
                              async_metadata.has_time_spec,
                              async_metadata.has_time_spec
                                  ? async_metadata.time_spec.to_ticks(rate)
                                  : 0});
    }

    receiver.join();
    if (records.empty()) {
      std::cerr << "no RX samples received\n";
      return 3;
    }

    std::vector<double> powers;
    powers.reserve(records.size());
    for (const auto& record : records) {
      powers.push_back(record.power);
    }
    std::sort(powers.begin(), powers.end());
    const double median = powers[powers.size() / 2];
    const auto peak = std::max_element(records.begin(), records.end(),
        [](const power_record& lhs, const power_record& rhs) { return lhs.power < rhs.power; });

    std::cout << std::fixed << std::setprecision(9)
              << "mode=" << mode
              << " rate=" << rate
              << " clock=" << clock_source
              << " tx_gain=" << tx_gain
              << " requested=" << burst_samples
              << " sent=" << sent
              << " tx_before_tick=" << before_send.to_ticks(rate)
              << " target_tick=" << metadata.time_spec.to_ticks(rate)
              << " tx_after_tick=" << after_send.to_ticks(rate)
              << " async_events=" << async_events.size();
    for (const auto& event : async_events) {
      std::cout << " {code=0x" << std::hex << static_cast<unsigned>(event.code)
                << std::dec << ",has_time=" << (event.has_time ? 1 : 0)
                << ",tick=" << event.tick << '}';
    }
    std::cout << '\n'
              << "rx_records=" << records.size()
              << " median_power=" << median
              << " peak_power=" << peak->power
              << " peak_over_median=" << (median > 0.0 ? peak->power / median : 0.0)
              << " peak_tick=" << peak->tick
              << " peak_samples=" << peak->samples << '\n';
    return sent == burst.size() ? 0 : 4;
  } catch (const std::exception& error) {
    std::cerr << "error: " << error.what() << '\n';
    return 1;
  }
}
