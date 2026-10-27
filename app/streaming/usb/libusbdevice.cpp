#include "usbipexport.h"

#include <libusb.h>

#include <atomic>
#include <cerrno>
#include <cstring>
#include <map>
#include <mutex>
#include <thread>

namespace usbip {

namespace {

// One libusb context and event thread for the whole process
class Context {
public:
    static Context &get()
    {
        static Context context;
        return context;
    }

    libusb_context *ctx() const { return m_Ctx; }

    void addUser()
    {
        std::lock_guard<std::mutex> lg(m_Lock);
        if (m_Users++ == 0) {
            m_Running = true;
            m_Thread = std::thread([this] {
                while (m_Running) {
                    timeval tv = {0, 100 * 1000};
                    libusb_handle_events_timeout_completed(m_Ctx, &tv, nullptr);
                }
            });
        }
    }

    void removeUser()
    {
        std::lock_guard<std::mutex> lg(m_Lock);
        if (--m_Users == 0) {
            m_Running = false;
            m_Thread.join();
        }
    }

private:
    Context() { libusb_init(&m_Ctx); }
    ~Context()
    {
        if (m_Ctx) {
            libusb_exit(m_Ctx);
        }
    }

    libusb_context *m_Ctx = nullptr;
    std::mutex m_Lock;
    int m_Users = 0;
    std::atomic<bool> m_Running {false};
    std::thread m_Thread;
};

std::string busidOf(libusb_device *dev)
{
    uint8_t ports[8];
    int count = libusb_get_port_numbers(dev, ports, sizeof(ports));
    std::string id = std::to_string(libusb_get_bus_number(dev)) + "-";
    for (int i = 0; i < count; i++) {
        id += (i ? "." : "") + std::to_string(ports[i]);
    }
    return id;
}

uint32_t usbipSpeed(int libusbSpeed)
{
    switch (libusbSpeed) {
    case LIBUSB_SPEED_LOW: return 1;
    case LIBUSB_SPEED_FULL: return 2;
    case LIBUSB_SPEED_HIGH: return 3;
    case LIBUSB_SPEED_SUPER:
    case LIBUSB_SPEED_SUPER_PLUS: return 5;
    default: return 2;
    }
}

int32_t errnoOf(libusb_transfer_status status)
{
    switch (status) {
    case LIBUSB_TRANSFER_COMPLETED: return 0;
    case LIBUSB_TRANSFER_STALL: return -EPIPE;
    case LIBUSB_TRANSFER_NO_DEVICE: return -ENODEV;
    case LIBUSB_TRANSFER_TIMED_OUT: return -ETIMEDOUT;
    case LIBUSB_TRANSFER_OVERFLOW: return -EOVERFLOW;
    case LIBUSB_TRANSFER_CANCELLED: return -ECONNRESET;
    default: return -EPROTO;
    }
}

DeviceInfo describe(libusb_device *dev, const libusb_device_descriptor &desc, libusb_device_handle *handle)
{
    DeviceInfo info;
    info.busid = busidOf(dev);
    info.path = "libusb/" + info.busid;
    info.busnum = libusb_get_bus_number(dev);
    info.devnum = libusb_get_device_address(dev);
    info.speed = usbipSpeed(libusb_get_device_speed(dev));
    info.idVendor = desc.idVendor;
    info.idProduct = desc.idProduct;
    info.bcdDevice = desc.bcdDevice;
    info.bDeviceClass = desc.bDeviceClass;
    info.bDeviceSubClass = desc.bDeviceSubClass;
    info.bDeviceProtocol = desc.bDeviceProtocol;
    info.bNumConfigurations = desc.bNumConfigurations;

    libusb_config_descriptor *config = nullptr;
    if (libusb_get_active_config_descriptor(dev, &config) == 0) {
        info.bConfigurationValue = config->bConfigurationValue;
        info.bNumInterfaces = config->bNumInterfaces;
        libusb_free_config_descriptor(config);
    }

    if (handle && desc.iProduct) {
        unsigned char name[128];
        if (libusb_get_string_descriptor_ascii(handle, desc.iProduct, name, sizeof(name)) > 0) {
            info.name = reinterpret_cast<char *>(name);
        }
    }
    if (info.name.empty()) {
        char ids[16];
        snprintf(ids, sizeof(ids), "%04x:%04x", desc.idVendor, desc.idProduct);
        info.name = ids;
    }
    return info;
}

class LibusbDevice : public Backend {
public:
    LibusbDevice(libusb_device_handle *handle, DeviceInfo info)
        : m_Handle(handle), m_Info(std::move(info))
    {
        Context::get().addUser();
        libusb_set_auto_detach_kernel_driver(m_Handle, 1);
        claimInterfaces();
    }

    ~LibusbDevice() override
    {
        // Cancel everything in flight and wait for libusb to hand the transfers back
        {
            std::lock_guard<std::mutex> lg(m_Lock);
            m_Closing = true;
            for (auto &[seqnum, transfer] : m_Pending) {
                libusb_cancel_transfer(transfer);
            }
        }
        while (true) {
            {
                std::lock_guard<std::mutex> lg(m_Lock);
                if (m_Pending.empty()) {
                    break;
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }

        releaseInterfaces();
        libusb_close(m_Handle);
        Context::get().removeUser();
    }

    DeviceInfo info() const override { return m_Info; }

    void submit(Urb &&urb) override
    {
        if (urb.endpoint == 0 && handleStandardRequest(urb)) {
            return;
        }

        auto transfer = libusb_alloc_transfer(0);
        auto ctx = new TransferContext {this, urb.seqnum, urb.in};

        if (urb.endpoint == 0) {
            // libusb wants the setup packet in front of the data
            uint16_t length = urb.setup[6] | urb.setup[7] << 8;
            ctx->buffer.resize(LIBUSB_CONTROL_SETUP_SIZE + length);
            memcpy(ctx->buffer.data(), urb.setup, 8);
            if (!urb.in) {
                memcpy(ctx->buffer.data() + 8, urb.data.data(), std::min<size_t>(length, urb.data.size()));
            }
            libusb_fill_control_transfer(transfer, m_Handle, ctx->buffer.data(), &LibusbDevice::done, ctx, 0);
        } else {
            uint8_t address = urb.endpoint | (urb.in ? LIBUSB_ENDPOINT_IN : LIBUSB_ENDPOINT_OUT);
            ctx->buffer = std::move(urb.data);
            if (endpointType(address) == LIBUSB_TRANSFER_TYPE_INTERRUPT) {
                libusb_fill_interrupt_transfer(transfer, m_Handle, address, ctx->buffer.data(), (int)ctx->buffer.size(), &LibusbDevice::done, ctx, 0);
            } else {
                libusb_fill_bulk_transfer(transfer, m_Handle, address, ctx->buffer.data(), (int)ctx->buffer.size(), &LibusbDevice::done, ctx, 0);
            }
        }

        std::lock_guard<std::mutex> lg(m_Lock);
        int err = libusb_submit_transfer(transfer);
        if (err) {
            Completion c;
            c.seqnum = urb.seqnum;
            c.in = urb.in;
            c.status = err == LIBUSB_ERROR_NO_DEVICE ? -ENODEV : -EPIPE;
            delete ctx;
            libusb_free_transfer(transfer);
            complete(std::move(c));
            return;
        }
        m_Pending[urb.seqnum] = transfer;
    }

    bool unlink(uint32_t seqnum) override
    {
        std::lock_guard<std::mutex> lg(m_Lock);
        auto it = m_Pending.find(seqnum);
        if (it == m_Pending.end()) {
            return false;
        }
        auto ctx = static_cast<TransferContext *>(it->second->user_data);
        ctx->unlinked = true;
        libusb_cancel_transfer(it->second);
        return true;
    }

private:
    struct TransferContext {
        LibusbDevice *device;
        uint32_t seqnum;
        bool in;
        std::vector<uint8_t> buffer;
        bool unlinked = false;
    };

    static void LIBUSB_CALL done(libusb_transfer *transfer)
    {
        auto ctx = static_cast<TransferContext *>(transfer->user_data);
        auto self = ctx->device;

        bool report;
        {
            std::lock_guard<std::mutex> lg(self->m_Lock);
            self->m_Pending.erase(ctx->seqnum);
            // An unlinked transfer is answered by the unlink reply alone
            report = !ctx->unlinked && !self->m_Closing;
        }

        if (report) {
            Completion c;
            c.seqnum = ctx->seqnum;
            c.in = ctx->in;
            c.status = errnoOf(transfer->status);
            if (transfer->type == LIBUSB_TRANSFER_TYPE_CONTROL) {
                if (ctx->in) {
                    auto data = ctx->buffer.data() + LIBUSB_CONTROL_SETUP_SIZE;
                    c.data.assign(data, data + transfer->actual_length);
                } else {
                    c.actualLength = transfer->actual_length;
                }
            } else if (ctx->in) {
                c.data.assign(ctx->buffer.begin(), ctx->buffer.begin() + transfer->actual_length);
            } else {
                c.actualLength = transfer->actual_length;
            }
            self->complete(std::move(c));
        }

        delete ctx;
        libusb_free_transfer(transfer);
    }

    // Requests that change device state must go through libusb's own calls,
    // or the local kernel loses track of the device
    bool handleStandardRequest(const Urb &urb)
    {
        uint8_t requestType = urb.setup[0];
        uint8_t request = urb.setup[1];
        uint16_t value = urb.setup[2] | urb.setup[3] << 8;
        uint16_t index = urb.setup[4] | urb.setup[5] << 8;

        int err;
        if (requestType == 0x00 && request == LIBUSB_REQUEST_SET_CONFIGURATION) {
            releaseInterfaces();
            err = libusb_set_configuration(m_Handle, value);
            claimInterfaces();
        } else if (requestType == 0x01 && request == LIBUSB_REQUEST_SET_INTERFACE) {
            err = libusb_set_interface_alt_setting(m_Handle, index, value);
        } else if (requestType == 0x02 && request == LIBUSB_REQUEST_CLEAR_FEATURE && value == 0) {
            err = libusb_clear_halt(m_Handle, (uint8_t)index);
        } else {
            return false;
        }

        Completion c;
        c.seqnum = urb.seqnum;
        c.in = urb.in;
        c.status = err ? -EPIPE : 0;
        complete(std::move(c));
        return true;
    }

    void claimInterfaces()
    {
        libusb_config_descriptor *config = nullptr;
        if (libusb_get_active_config_descriptor(libusb_get_device(m_Handle), &config)) {
            return;
        }
        m_EndpointTypes.clear();
        for (int i = 0; i < config->bNumInterfaces; i++) {
            if (libusb_claim_interface(m_Handle, i) == 0) {
                m_Claimed.push_back(i);
            }
            for (int a = 0; a < config->interface[i].num_altsetting; a++) {
                auto &alt = config->interface[i].altsetting[a];
                for (int e = 0; e < alt.bNumEndpoints; e++) {
                    m_EndpointTypes[alt.endpoint[e].bEndpointAddress] = alt.endpoint[e].bmAttributes & 3;
                }
            }
        }
        libusb_free_config_descriptor(config);
    }

    void releaseInterfaces()
    {
        for (int i : m_Claimed) {
            libusb_release_interface(m_Handle, i);
        }
        m_Claimed.clear();
    }

    int endpointType(uint8_t address) const
    {
        auto it = m_EndpointTypes.find(address);
        return it == m_EndpointTypes.end() ? LIBUSB_TRANSFER_TYPE_BULK : it->second;
    }

    libusb_device_handle *m_Handle;
    DeviceInfo m_Info;
    std::mutex m_Lock;
    std::map<uint32_t, libusb_transfer *> m_Pending;
    std::map<uint8_t, int> m_EndpointTypes;
    std::vector<int> m_Claimed;
    bool m_Closing = false;
};

}  // namespace

std::vector<DeviceInfo> listLocalDevices()
{
    std::vector<DeviceInfo> devices;
    libusb_device **list = nullptr;
    ssize_t count = libusb_get_device_list(Context::get().ctx(), &list);
    for (ssize_t i = 0; i < count; i++) {
        libusb_device_descriptor desc;
        if (libusb_get_device_descriptor(list[i], &desc) || desc.bDeviceClass == LIBUSB_CLASS_HUB) {
            continue;
        }
        libusb_device_handle *handle = nullptr;
        libusb_open(list[i], &handle);
        devices.push_back(describe(list[i], desc, handle));
        if (handle) {
            libusb_close(handle);
        }
    }
    libusb_free_device_list(list, 1);
    return devices;
}

std::unique_ptr<Backend> openLocalDevice(const std::string &busid, std::string &error)
{
    std::unique_ptr<Backend> backend;
    libusb_device **list = nullptr;
    ssize_t count = libusb_get_device_list(Context::get().ctx(), &list);
    for (ssize_t i = 0; i < count; i++) {
        if (busidOf(list[i]) != busid) {
            continue;
        }
        libusb_device_descriptor desc;
        libusb_get_device_descriptor(list[i], &desc);
        libusb_device_handle *handle = nullptr;
        int err = libusb_open(list[i], &handle);
        if (err) {
            error = std::string("opening ") + busid + ": " + libusb_strerror((libusb_error)err) +
                    (err == LIBUSB_ERROR_ACCESS ? " (no permission for this USB device)" : "");
            break;
        }
        backend = std::make_unique<LibusbDevice>(handle, describe(list[i], desc, handle));
        break;
    }
    libusb_free_device_list(list, 1);
    if (!backend && error.empty()) {
        error = "no USB device " + busid;
    }
    return backend;
}

}  // namespace usbip
