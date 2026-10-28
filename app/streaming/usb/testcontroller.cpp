#include "usbipexport.h"

#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstring>
#include <deque>
#include <mutex>

namespace usbip {

namespace {

// pid.codes test VID/PID, reserved for exactly this kind of thing
constexpr uint16_t kVendor = 0x1209;
constexpr uint16_t kProduct = 0x0001;

const uint8_t kDeviceDescriptor[] = {
    18, 1,          // bLength, DEVICE
    0x00, 0x02,     // USB 2.0
    0, 0, 0,        // class defined per interface
    64,             // bMaxPacketSize0
    kVendor & 0xff, kVendor >> 8,
    kProduct & 0xff, kProduct >> 8,
    0x00, 0x01,     // bcdDevice 1.00
    1, 2, 0,        // manufacturer, product, no serial
    1,              // one configuration
};

// 16 buttons, then X Y Z Rz as 0..255
const uint8_t kReportDescriptor[] = {
    0x05, 0x01,  // Usage Page (Generic Desktop)
    0x09, 0x05,  // Usage (Game Pad)
    0xa1, 0x01,  // Collection (Application)
    0x05, 0x09,  //   Usage Page (Button)
    0x19, 0x01,  //   Usage Minimum (1)
    0x29, 0x10,  //   Usage Maximum (16)
    0x15, 0x00,  //   Logical Minimum (0)
    0x25, 0x01,  //   Logical Maximum (1)
    0x75, 0x01,  //   Report Size (1)
    0x95, 0x10,  //   Report Count (16)
    0x81, 0x02,  //   Input (Data, Var, Abs)
    0x05, 0x01,  //   Usage Page (Generic Desktop)
    0x09, 0x30,  //   Usage (X)
    0x09, 0x31,  //   Usage (Y)
    0x09, 0x32,  //   Usage (Z)
    0x09, 0x35,  //   Usage (Rz)
    0x15, 0x00,  //   Logical Minimum (0)
    0x26, 0xff, 0x00,  // Logical Maximum (255)
    0x75, 0x08,  //   Report Size (8)
    0x95, 0x04,  //   Report Count (4)
    0x81, 0x02,  //   Input (Data, Var, Abs)
    0xc0,        // End Collection
};

constexpr uint8_t kReportSize = 6;

const uint8_t kConfigDescriptor[] = {
    9, 2, 34, 0,    // CONFIGURATION, total length 34
    1, 1, 0,        // one interface, value 1, no string
    0x80, 50,       // bus powered, 100 mA
    9, 4, 0, 0,     // INTERFACE 0, alt 0
    1, 3, 0, 0, 0,  // one endpoint, HID, no subclass/protocol, no string
    9, 0x21,        // HID
    0x11, 0x01, 0, 1,
    0x22, sizeof(kReportDescriptor), 0,
    7, 5, 0x81, 3,  // ENDPOINT 1 IN, interrupt
    kReportSize, 0, 4,  // max packet, bInterval 4 ms
};

std::vector<uint8_t> stringDescriptor(const char *s)
{
    std::vector<uint8_t> d = {0, 3};
    for (; *s; s++) {
        d.push_back((uint8_t)*s);
        d.push_back(0);
    }
    d[0] = (uint8_t)d.size();
    return d;
}

class TestController : public Backend {
public:
    explicit TestController(std::string busid)
        : m_Busid(std::move(busid)),
          m_Start(std::chrono::steady_clock::now())
    {
    }

    DeviceInfo info() const override
    {
        DeviceInfo i;
        i.busid = m_Busid;
        i.path = "stand-in/test-controller";
        i.name = "Test Controller";
        i.manufacturer = "Stand-In";
        i.interfaceClasses = {3};  // HID
        i.busnum = 1;
        i.devnum = 1;
        i.speed = 2;  // full speed
        i.idVendor = kVendor;
        i.idProduct = kProduct;
        i.bcdDevice = 0x0100;
        return i;
    }

    void submit(Urb &&urb) override
    {
        if (urb.endpoint == 0) {
            control(std::move(urb));
        } else if (urb.endpoint == 1 && urb.in) {
            // Answered from poll() at the endpoint's interval
            std::lock_guard<std::mutex> lg(m_Lock);
            m_PendingIn.push_back(std::move(urb));
        } else {
            reply(urb, -EPIPE, {});
        }
    }

    bool unlink(uint32_t seqnum) override
    {
        std::lock_guard<std::mutex> lg(m_Lock);
        for (auto it = m_PendingIn.begin(); it != m_PendingIn.end(); ++it) {
            if (it->seqnum == seqnum) {
                m_PendingIn.erase(it);
                return true;
            }
        }
        return false;
    }

    void poll() override
    {
        auto now = std::chrono::steady_clock::now();
        if (now - m_LastReport < std::chrono::milliseconds(4)) {
            return;
        }
        m_LastReport = now;

        Urb urb;
        {
            std::lock_guard<std::mutex> lg(m_Lock);
            if (m_PendingIn.empty()) {
                return;
            }
            urb = std::move(m_PendingIn.front());
            m_PendingIn.pop_front();
        }

        // Sticks circle and buttons count up so a viewer can see it's alive
        double t = std::chrono::duration<double>(now - m_Start).count();
        uint16_t buttons = (uint16_t)(1u << ((int)t % 16));
        std::vector<uint8_t> report = {
            (uint8_t)(buttons & 0xff), (uint8_t)(buttons >> 8),
            (uint8_t)(128 + 127 * std::cos(t)), (uint8_t)(128 + 127 * std::sin(t)),
            (uint8_t)(128 + 127 * std::cos(t * 2)), (uint8_t)(128 + 127 * std::sin(t * 2)),
        };
        report.resize(std::min<size_t>(report.size(), urb.data.size()));
        reply(urb, 0, std::move(report));
    }

private:
    void control(Urb &&urb)
    {
        uint8_t requestType = urb.setup[0];
        uint8_t request = urb.setup[1];
        uint16_t value = urb.setup[2] | urb.setup[3] << 8;
        uint16_t length = urb.setup[6] | urb.setup[7] << 8;

        auto send = [&](const uint8_t *p, size_t size) {
            reply(urb, 0, std::vector<uint8_t>(p, p + std::min<size_t>(size, length)));
        };

        if (request == 6 && (requestType == 0x80 || requestType == 0x81)) {  // GET_DESCRIPTOR
            switch (value >> 8) {
            case 1:
                return send(kDeviceDescriptor, sizeof(kDeviceDescriptor));
            case 2:
                return send(kConfigDescriptor, sizeof(kConfigDescriptor));
            case 3: {
                static const uint8_t languages[] = {4, 3, 0x09, 0x04};
                auto index = value & 0xff;
                if (index == 0) {
                    return send(languages, sizeof(languages));
                }
                auto s = stringDescriptor(index == 1 ? "Stand-In" : "Test Controller");
                return send(s.data(), s.size());
            }
            case 0x22:
                return send(kReportDescriptor, sizeof(kReportDescriptor));
            }
        } else if (request == 0 && (requestType & 0x80)) {  // GET_STATUS
            static const uint8_t status[] = {0, 0};
            return send(status, sizeof(status));
        } else if (request == 8 && requestType == 0x80) {  // GET_CONFIGURATION
            static const uint8_t config[] = {1};
            return send(config, sizeof(config));
        } else if ((request == 9 && requestType == 0x00) ||    // SET_CONFIGURATION
                   (request == 11 && requestType == 0x01) ||   // SET_INTERFACE
                   (request == 0x0a && requestType == 0x21) || // HID SET_IDLE
                   (request == 0x0b && requestType == 0x21)) { // HID SET_PROTOCOL
            return reply(urb, 0, {});
        }

        reply(urb, -EPIPE, {});
    }

    void reply(const Urb &urb, int32_t status, std::vector<uint8_t> data)
    {
        Completion c;
        c.seqnum = urb.seqnum;
        c.in = urb.in;
        c.status = status;
        c.actualLength = urb.in ? 0 : (uint32_t)urb.data.size();
        c.data = std::move(data);
        complete(std::move(c));
    }

    std::string m_Busid;
    std::mutex m_Lock;
    std::deque<Urb> m_PendingIn;
    std::chrono::steady_clock::time_point m_Start;
    std::chrono::steady_clock::time_point m_LastReport;
};

}  // namespace

std::unique_ptr<Backend> makeTestController(const std::string &busid)
{
    return std::make_unique<TestController>(busid);
}

}  // namespace usbip
