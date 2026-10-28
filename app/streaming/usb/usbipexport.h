#pragma once

// Forwards one local USB device to a Stand-In server over USB/IP.
//
// The connection is a paired HTTPS connection upgraded to "stand-in-usb"; inside
// it this side acts as the USB/IP server for one device and the Stand-In server
// attaches it to a virtual host controller. Nothing here depends on Qt, so the
// same code can run in the desktop client, a test tool, or behind JNI on Android.

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

typedef struct ssl_st SSL;

namespace usbip {

// What the remote host needs to know about the device to attach it
struct DeviceInfo {
    std::string busid;   // client-local id, e.g. "1-2.3"
    std::string path;    // free-form, shown in logs
    std::string name;
    std::string manufacturer;
    std::vector<uint8_t> interfaceClasses;  // one per interface of the active configuration
    bool accessible = true;                 // this user is allowed to open it
    uint32_t busnum = 0;
    uint32_t devnum = 0;
    uint32_t speed = 0;  // Linux usb_device_speed: 1 low, 2 full, 3 high, 5 super
    uint16_t idVendor = 0;
    uint16_t idProduct = 0;
    uint16_t bcdDevice = 0;
    uint8_t bDeviceClass = 0;
    uint8_t bDeviceSubClass = 0;
    uint8_t bDeviceProtocol = 0;
    uint8_t bConfigurationValue = 1;
    uint8_t bNumConfigurations = 1;
    uint8_t bNumInterfaces = 1;
};

// One USB request from the remote host
struct Urb {
    uint32_t seqnum = 0;
    bool in = false;
    uint8_t endpoint = 0;  // number without the direction bit
    uint8_t setup[8] = {};
    std::vector<uint8_t> data;  // OUT payload, or IN buffer sized to the requested length
};

// Result of a Urb; status is a negative errno as the kernel expects (0 on success)
struct Completion {
    uint32_t seqnum = 0;
    bool in = false;
    int32_t status = 0;
    std::vector<uint8_t> data;  // IN data actually transferred
    uint32_t actualLength = 0;  // OUT bytes actually transferred
};

class Backend {
public:
    using CompleteFn = std::function<void(Completion &&)>;

    virtual ~Backend() = default;

    virtual DeviceInfo info() const = 0;

    // Must eventually call complete() exactly once per Urb unless it's unlinked first.
    // May be called back from any thread.
    virtual void submit(Urb &&urb) = 0;

    // Cancel a pending Urb. Returns true if it was still pending and will not complete.
    virtual bool unlink(uint32_t seqnum) = 0;

    // Called by the exporter roughly every millisecond, for backends that generate data
    virtual void poll() {}

    void setCompleteFn(CompleteFn fn) { m_Complete = std::move(fn); }

protected:
    void complete(Completion &&c) { m_Complete(std::move(c)); }

private:
    CompleteFn m_Complete;
};

// Built-in HID gamepad with moving sticks, for testing the whole path without hardware
std::unique_ptr<Backend> makeTestController(const std::string &busid = "test-1");

// Every device on this machine that can be forwarded
std::vector<DeviceInfo> listLocalDevices();

// Open a local device by busid; nullptr if it can't be claimed
std::unique_ptr<Backend> openLocalDevice(const std::string &busid, std::string &error);

struct ServerIdentity {
    std::string host;
    uint16_t httpsPort = 47984;
    std::string clientCertPem;
    std::string clientKeyPem;
    std::string serverCertPem;  // pinned at pairing and must match; empty skips the check (test tool only)
};

// Connect, upgrade, export the device and serve it until the server or stop() ends it.
// Blocks; returns an empty string on a clean end, otherwise the reason it failed.
class Exporter {
public:
    Exporter(ServerIdentity server, std::unique_ptr<Backend> backend);
    ~Exporter();

    std::string run();
    void stop();

    // Called from run()'s thread once the server has attached the device
    std::function<void()> onAttached;

private:
    std::string handshake(SSL *ssl);
    std::string serve(SSL *ssl, int fd);

    ServerIdentity m_Server;
    std::unique_ptr<Backend> m_Backend;
    int m_WakePipe[2] = {-1, -1};
    struct Shared;
    std::shared_ptr<Shared> m_Shared;
};

}  // namespace usbip
