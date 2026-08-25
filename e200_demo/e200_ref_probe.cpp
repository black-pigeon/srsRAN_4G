#include <uhd/usrp/multi_usrp.hpp>

#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <string>
#include <thread>

int main(int argc, char** argv)
{
  const std::string address = argc > 1 ? argv[1] : "192.168.1.10";
  const std::string source = argc > 2 ? argv[2] : "external";
  const std::string args = "addr=" + address +
                           ",recv_frame_size=1472,send_frame_size=1472";

  try {
    auto usrp = uhd::usrp::multi_usrp::make(args);
    std::cout << "device=" << address << " clock_sources=";
    for (const auto& value : usrp->get_clock_sources(0)) {
      std::cout << value << ' ';
    }
    std::cout << '\n';

    usrp->set_clock_source(source);
    std::cout << "selected=" << usrp->get_clock_source(0) << '\n';

    bool locked = false;
    // The E200 VCXO loop normally locks in 17--18 seconds, but can take
    // longer after repeated source/rate reconfiguration.  Keep this probe
    // alive long enough to distinguish slow acquisition from a missing ref.
    for (unsigned attempt = 0; attempt != 200; ++attempt) {
      const auto sensor = usrp->get_mboard_sensor("ref_locked");
      locked = sensor.to_bool();
      std::cout << "ref_locked[" << attempt << "]="
                << (locked ? "true" : "false") << '\n';
      if (locked || source == "internal") {
        break;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(250));
    }

    usrp->set_rx_rate(5.76e6);
    usrp->set_time_now(uhd::time_spec_t(0.0));
    const auto wall0 = std::chrono::steady_clock::now();
    const auto time0 = usrp->get_time_now();
    std::this_thread::sleep_for(std::chrono::seconds(2));
    const auto wall1 = std::chrono::steady_clock::now();
    const auto time1 = usrp->get_time_now();
    const double wall_seconds = std::chrono::duration<double>(wall1 - wall0).count();
    const double fpga_seconds = time1.get_real_secs() - time0.get_real_secs();
    std::cout << std::fixed << std::setprecision(9)
              << "wall_seconds=" << wall_seconds
              << " fpga_seconds=" << fpga_seconds
              << " error_ppm=" << (fpga_seconds / wall_seconds - 1.0) * 1e6
              << '\n';
    return locked ? EXIT_SUCCESS : 2;
  } catch (const std::exception& error) {
    std::cerr << "error: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
