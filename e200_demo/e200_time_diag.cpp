#include <uhd/stream.hpp>
#include <uhd/types/stream_cmd.hpp>
#include <uhd/usrp/multi_usrp.hpp>

#include <chrono>
#include <cmath>
#include <complex>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr double kRate = 5.76e6;

uint64_t ticks(const uhd::time_spec_t& time)
{
  return time.to_ticks(kRate);
}

} // namespace

int main(int argc, char** argv)
{
  const std::string address = argc > 1 ? argv[1] : "192.168.1.10";
  const std::string args = "addr=" + address + ",recv_frame_size=1472,send_frame_size=1472";

  try {
    auto usrp = uhd::usrp::multi_usrp::make(args);
    usrp->set_rx_rate(kRate, 0);
    usrp->set_tx_rate(kRate, 0);

    const double rx_rate = usrp->get_rx_rate(0);
    const double tx_rate = usrp->get_tx_rate(0);
    std::cout << std::fixed << std::setprecision(9)
              << "device=" << address << " rx_rate=" << rx_rate
              << " tx_rate=" << tx_rate << '\n';
    if (std::abs(rx_rate - kRate) > 1.0 || std::abs(tx_rate - kRate) > 1.0) {
      std::cerr << "sample-rate readback mismatch\n";
      return 2;
    }

    usrp->set_time_now(uhd::time_spec_t(0.0));
    std::this_thread::sleep_for(std::chrono::milliseconds(20));

    auto previous_wall = std::chrono::steady_clock::now();
    auto previous_hw = usrp->get_time_now();
    std::cout << "time[0] sec=" << previous_hw.get_real_secs()
              << " ticks=" << ticks(previous_hw) << '\n';
    for (unsigned i = 1; i <= 5; ++i) {
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
      const auto wall = std::chrono::steady_clock::now();
      const auto hw = usrp->get_time_now();
      const double wall_delta = std::chrono::duration<double>(wall - previous_wall).count();
      const int64_t hw_delta = static_cast<int64_t>(ticks(hw) - ticks(previous_hw));
      std::cout << "time[" << i << "] sec=" << hw.get_real_secs()
                << " ticks=" << ticks(hw)
                << " delta_ticks=" << hw_delta
                << " expected_ticks=" << static_cast<int64_t>(std::llround(wall_delta * kRate))
                << '\n';
      previous_wall = wall;
      previous_hw = hw;
    }

    uhd::stream_args_t stream_args("sc16", "sc16");
    stream_args.channels = {0};
    auto rx = usrp->get_rx_stream(stream_args);
    std::vector<std::complex<int16_t>> samples(rx->get_max_num_samps());

    uhd::stream_cmd_t command(uhd::stream_cmd_t::STREAM_MODE_START_CONTINUOUS);
    command.stream_now = true;
    rx->issue_stream_cmd(command);

    const auto before = usrp->get_time_now();
    uhd::rx_metadata_t metadata;
    const size_t received = rx->recv(samples.data(), samples.size(), metadata, 2.0, true);
    const auto after = usrp->get_time_now();

    command.stream_mode = uhd::stream_cmd_t::STREAM_MODE_STOP_CONTINUOUS;
    rx->issue_stream_cmd(command);

    std::cout << "rx received=" << received
              << " error=" << metadata.strerror()
              << " has_time=" << metadata.has_time_spec;
    if (metadata.has_time_spec) {
      std::cout << " metadata_ticks=" << ticks(metadata.time_spec)
                << " before_ticks=" << ticks(before)
                << " after_ticks=" << ticks(after)
                << " metadata_minus_before="
                << static_cast<int64_t>(ticks(metadata.time_spec) - ticks(before));
    }
    std::cout << '\n';
    return received == 0 || metadata.error_code != uhd::rx_metadata_t::ERROR_CODE_NONE ? 3 : 0;
  } catch (const std::exception& error) {
    std::cerr << "error: " << error.what() << '\n';
    return 1;
  }
}
