// Forward a USB device (or the built-in test controller) to a Stand-In server.
//   stand-in-usb list
//   stand-in-usb <host> <client-cert.pem> <client-key.pem> <busid|test> [server-cert.pem]
#include "../app/streaming/usb/usbipexport.h"

#include <csignal>
#include <cstdio>
#include <fstream>
#include <sstream>

static usbip::Exporter *g_Exporter;

static std::string slurp(const char *path)
{
    std::ifstream in(path);
    std::stringstream s;
    s << in.rdbuf();
    return s.str();
}

int main(int argc, char **argv)
{
    if (argc == 2 && std::string(argv[1]) == "list") {
        for (auto &d : usbip::listLocalDevices()) {
            printf("%-10s %04x:%04x  %s\n", d.busid.c_str(), d.idVendor, d.idProduct, d.name.c_str());
        }
        return 0;
    }
    if (argc != 5 && argc != 6) {
        fprintf(stderr, "usage: %s list | <host> <cert.pem> <key.pem> <busid|test> [server-cert.pem]\n", argv[0]);
        return 2;
    }

    std::string error;
    std::string busid = argv[4];
    auto backend = busid == "test" ? usbip::makeTestController() : usbip::openLocalDevice(busid, error);
    if (!backend) {
        fprintf(stderr, "%s\n", error.c_str());
        return 1;
    }

    usbip::ServerIdentity server;
    server.host = argv[1];
    server.clientCertPem = slurp(argv[2]);
    server.clientKeyPem = slurp(argv[3]);
    if (argc == 6) {
        server.serverCertPem = slurp(argv[5]);
    }

    usbip::Exporter exporter(server, std::move(backend));
    g_Exporter = &exporter;
    signal(SIGINT, [](int) { g_Exporter->stop(); });
    signal(SIGTERM, [](int) { g_Exporter->stop(); });

    printf("Forwarding %s to %s, Ctrl+C to stop\n", busid.c_str(), argv[1]);
    error = exporter.run();
    if (!error.empty()) {
        fprintf(stderr, "Stopped: %s\n", error.c_str());
        return 1;
    }
    printf("Stopped\n");
    return 0;
}
