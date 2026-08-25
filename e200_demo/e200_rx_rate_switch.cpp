#include <uhd/stream.hpp>
#include <uhd/types/stream_cmd.hpp>
#include <uhd/usrp/multi_usrp.hpp>

#include <complex>
#include <chrono>
#include <cstdlib>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

int main(int argc, char** argv)
{
  const std::string address = argc > 1 ? argv[1] : "192.168.10.2";
  const std::string args = "addr=" + address +
      ",recv_frame_size=1472,send_frame_size=1472,clock_source=external";

  try {
    auto usrp = uhd::usrp::multi_usrp::make(args);
    usrp->set_clock_source("external");
    usrp->set_rx_freq(2680e6);
    usrp->set_rx_gain(40.0);

    std::vector<double> rates;
    for (int index = 2; index < argc; ++index) {
      rates.push_back(std::stod(argv[index]));
    }
    if (rates.empty()) {
      rates = {1.92e6, 5.76e6, 1.92e6, 5.76e6};
    }
    size_t packet_target = 20;
    if (const char* value = std::getenv("E200_RATE_TEST_PACKETS")) {
      packet_target = std::stoul(value);
    }
    for (size_t epoch = 0; epoch != rates.size(); ++epoch) {
      const double requested_rate = rates[epoch];
      const double device_time_before = usrp->get_time_now().get_real_secs();
      const auto host_time_before = std::chrono::steady_clock::now();
      usrp->set_rx_rate(requested_rate);
      const auto host_time_after = std::chrono::steady_clock::now();
      const double device_time_after = usrp->get_time_now().get_real_secs();
      const double host_elapsed = std::chrono::duration<double>(
          host_time_after - host_time_before).count();

      std::cout << std::fixed << std::setprecision(6)
                << "epoch=" << epoch
                << " rate_change=" << static_cast<uint64_t>(requested_rate)
                << " device_before=" << device_time_before
                << " device_after=" << device_time_after
                << " device_delta=" << (device_time_after - device_time_before)
                << " host_delta=" << host_elapsed << '\n';

      uhd::stream_args_t stream_args("fc32", "sc16");
      stream_args.channels = {0};
      auto stream = usrp->get_rx_stream(stream_args);
      std::vector<std::complex<float>> samples(stream->get_max_num_samps());

      uhd::stream_cmd_t command(uhd::stream_cmd_t::STREAM_MODE_START_CONTINUOUS);
      command.stream_now = true;
      stream->issue_stream_cmd(command);

      size_t packets = 0;
      size_t total_samples = 0;
      uint64_t first_tick = 0;
      uint64_t last_tick = 0;
      size_t errors = 0;
      for (size_t attempt = 0;
           attempt != packet_target * 2 && packets != packet_target;
           ++attempt) {
        uhd::rx_metadata_t metadata;
        const size_t count = stream->recv(
            samples.data(), samples.size(), metadata, 0.1, true);
        if (metadata.error_code != uhd::rx_metadata_t::ERROR_CODE_NONE) {
          ++errors;
          std::cout << "epoch=" << epoch << " error="
                    << metadata.strerror() << " count=" << count << '\n';
          continue;
        }
        if (count == 0) {
          continue;
        }
        const uint64_t tick = metadata.time_spec.to_ticks(requested_rate);
        if (packets == 0) {
          first_tick = tick;
        }
        last_tick = tick;
        ++packets;
        total_samples += count;
      }

      command.stream_mode = uhd::stream_cmd_t::STREAM_MODE_STOP_CONTINUOUS;
      stream->issue_stream_cmd(command);
      std::cout << "epoch=" << epoch
                << " requested_rate=" << static_cast<uint64_t>(requested_rate)
                << " actual_rate=" << static_cast<uint64_t>(usrp->get_rx_rate())
                << " packets=" << packets
                << " samples=" << total_samples
                << " first_tick=" << first_tick
                << " last_tick=" << last_tick
                << " errors=" << errors << '\n';
      stream.reset();
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "error: " << error.what() << '\n';
    return 1;
  }
}
