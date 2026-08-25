#include <uhd/usrp/multi_usrp.hpp>

#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

int main(int argc, char** argv)
{
  if (argc != 2) {
    std::cerr << "usage: " << argv[0] << " <E200 IPv4 address>\n";
    return EXIT_FAILURE;
  }

  const std::string args = "type=E200,addr=" + std::string(argv[1]);
  auto              usrp = uhd::usrp::multi_usrp::make(args);
  const double      original = usrp->get_tx_gain(0);
  const auto        range = usrp->get_tx_gain_range(0);

  std::cout << std::fixed << std::setprecision(1)
            << "range=" << range.start() << ".." << range.stop()
            << " step=" << range.step() << " original=" << original << '\n';

  try {
    for (const double requested : std::vector<double>{0.0, 10.0, 37.6, 89.0, 120.0}) {
      usrp->set_tx_gain(requested, 0);
      std::cout << "requested=" << requested
                << " readback=" << usrp->get_tx_gain(0) << '\n';
    }
  } catch (...) {
    usrp->set_tx_gain(original, 0);
    throw;
  }

  usrp->set_tx_gain(original, 0);
  std::cout << "restored=" << usrp->get_tx_gain(0) << '\n';
  return EXIT_SUCCESS;
}
