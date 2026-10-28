#include "usbipexport.h"

#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>

#include <cerrno>
#include <cstring>
#include <deque>
#include <mutex>

namespace usbip {

namespace {

constexpr uint16_t kVersion = 0x0111;
constexpr uint16_t kOpReqImport = 0x8003;
constexpr uint16_t kOpRepImport = 0x0003;

constexpr uint32_t kCmdSubmit = 1;
constexpr uint32_t kCmdUnlink = 2;
constexpr uint32_t kRetSubmit = 3;
constexpr uint32_t kRetUnlink = 4;

constexpr size_t kHeaderSize = 48;

void put16(std::vector<uint8_t> &out, uint16_t v)
{
    out.push_back(v >> 8);
    out.push_back(v & 0xff);
}

void put32(std::vector<uint8_t> &out, uint32_t v)
{
    for (int shift = 24; shift >= 0; shift -= 8) {
        out.push_back((v >> shift) & 0xff);
    }
}

void putBytes(std::vector<uint8_t> &out, const std::string &s, size_t size)
{
    for (size_t i = 0; i < size; i++) {
        out.push_back(i < s.size() && i < size - 1 ? (uint8_t)s[i] : 0);
    }
}

uint32_t get32(const uint8_t *p)
{
    return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}

std::string sslError(const char *what)
{
    char buf[256];
    ERR_error_string_n(ERR_get_error(), buf, sizeof(buf));
    return std::string(what) + ": " + buf;
}

bool sslWriteAll(SSL *ssl, const void *data, size_t size)
{
    auto p = static_cast<const char *>(data);
    while (size > 0) {
        int n = SSL_write(ssl, p, (int)size);
        if (n <= 0) {
            return false;
        }
        p += n;
        size -= n;
    }
    return true;
}

bool sslReadAll(SSL *ssl, void *data, size_t size)
{
    auto p = static_cast<char *>(data);
    while (size > 0) {
        int n = SSL_read(ssl, p, (int)size);
        if (n <= 0) {
            return false;
        }
        p += n;
        size -= n;
    }
    return true;
}

int connectTcp(const std::string &host, uint16_t port, std::string &error)
{
    addrinfo hints = {};
    hints.ai_socktype = SOCK_STREAM;
    addrinfo *result = nullptr;
    int err = getaddrinfo(host.c_str(), std::to_string(port).c_str(), &hints, &result);
    if (err) {
        error = std::string("resolving ") + host + ": " + gai_strerror(err);
        return -1;
    }

    int fd = -1;
    for (auto ai = result; ai; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) {
            continue;
        }
        if (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0) {
            break;
        }
        close(fd);
        fd = -1;
    }
    freeaddrinfo(result);

    if (fd < 0) {
        error = "connecting to " + host + ": " + strerror(errno);
        return -1;
    }

    // USB traffic is small and latency sensitive
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    return fd;
}

}  // namespace

// Completions arrive from backend threads; the I/O thread sends them
struct Exporter::Shared {
    std::mutex lock;
    std::deque<Completion> done;
    int wakeFd = -1;
    bool stopping = false;
};

Exporter::Exporter(ServerIdentity server, std::unique_ptr<Backend> backend)
    : m_Server(std::move(server)),
      m_Backend(std::move(backend)),
      m_Shared(std::make_shared<Shared>())
{
    if (pipe(m_WakePipe) == 0) {
        m_Shared->wakeFd = m_WakePipe[1];
    }

    std::weak_ptr<Shared> weak = m_Shared;
    m_Backend->setCompleteFn([weak](Completion &&c) {
        auto shared = weak.lock();
        if (!shared) {
            return;
        }
        std::lock_guard<std::mutex> lg(shared->lock);
        shared->done.push_back(std::move(c));
        char b = 0;
        (void)!write(shared->wakeFd, &b, 1);
    });
}

Exporter::~Exporter()
{
    // Drop the backend first so no completion races the pipe closing
    m_Backend.reset();
    for (int fd : m_WakePipe) {
        if (fd >= 0) {
            close(fd);
        }
    }
}

void Exporter::stop()
{
    {
        std::lock_guard<std::mutex> lg(m_Shared->lock);
        m_Shared->stopping = true;
    }
    char b = 0;
    (void)!write(m_WakePipe[1], &b, 1);
}

static bool serverMatchesPin(SSL *ssl, const std::string &pinnedPem)
{
    BIO *bio = BIO_new_mem_buf(pinnedPem.data(), (int)pinnedPem.size());
    X509 *pinned = PEM_read_bio_X509(bio, nullptr, nullptr, nullptr);
    BIO_free(bio);
    X509 *peer = SSL_get1_peer_certificate(ssl);
    bool match = pinned && peer && X509_cmp(pinned, peer) == 0;
    X509_free(pinned);
    X509_free(peer);
    return match;
}

std::string Exporter::run()
{
    std::string error;

    SSL_CTX *ctx = SSL_CTX_new(TLS_client_method());
    BIO *certBio = BIO_new_mem_buf(m_Server.clientCertPem.data(), (int)m_Server.clientCertPem.size());
    BIO *keyBio = BIO_new_mem_buf(m_Server.clientKeyPem.data(), (int)m_Server.clientKeyPem.size());
    X509 *cert = PEM_read_bio_X509(certBio, nullptr, nullptr, nullptr);
    EVP_PKEY *key = PEM_read_bio_PrivateKey(keyBio, nullptr, nullptr, nullptr);
    BIO_free(certBio);
    BIO_free(keyBio);

    if (!cert || !key || SSL_CTX_use_certificate(ctx, cert) != 1 || SSL_CTX_use_PrivateKey(ctx, key) != 1) {
        error = sslError("loading the client identity");
        X509_free(cert);
        EVP_PKEY_free(key);
        SSL_CTX_free(ctx);
        return error;
    }
    X509_free(cert);
    EVP_PKEY_free(key);

    // The server's certificate was pinned at pairing time and is checked after the
    // handshake; the server, in turn, only accepts clients it paired with
    SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, nullptr);

    int fd = connectTcp(m_Server.host, m_Server.httpsPort, error);
    if (fd < 0) {
        SSL_CTX_free(ctx);
        return error;
    }

    SSL *ssl = SSL_new(ctx);
    SSL_set_fd(ssl, fd);
    if (SSL_connect(ssl) != 1) {
        error = sslError("TLS handshake");
    } else if (!m_Server.serverCertPem.empty() && !serverMatchesPin(ssl, m_Server.serverCertPem)) {
        error = "the server's certificate doesn't match the one saved when pairing";
    } else {
        error = handshake(ssl);
        if (error.empty()) {
            if (onAttached) {
                onAttached();
            }
            error = serve(ssl, fd);
        }
        SSL_shutdown(ssl);
    }

    SSL_free(ssl);
    close(fd);
    SSL_CTX_free(ctx);
    return error;
}

std::string Exporter::handshake(SSL *ssl)
{
    DeviceInfo info = m_Backend->info();

    std::string request = "GET /usb HTTP/1.1\r\n"
                          "Host: " + m_Server.host + "\r\n"
                          "Connection: Upgrade\r\n"
                          "Upgrade: stand-in-usb\r\n"
                          "X-Usb-Busid: " + info.busid + "\r\n"
                          "\r\n";
    if (!sslWriteAll(ssl, request.data(), request.size())) {
        return "sending the upgrade request failed";
    }

    // Read the response header byte by byte, so nothing after it is consumed
    std::string response;
    while (response.size() < 4096 && (response.size() < 4 || response.compare(response.size() - 4, 4, "\r\n\r\n") != 0)) {
        char c;
        if (SSL_read(ssl, &c, 1) != 1) {
            return "the server closed the connection; it may not support USB forwarding or this client isn't paired";
        }
        response += c;
    }
    if (response.compare(0, 12, "HTTP/1.1 101") != 0) {
        return "the server refused USB forwarding: " + response.substr(0, response.find('\r'));
    }

    // The server imports the device by busid
    uint8_t req[8 + 32];
    if (!sslReadAll(ssl, req, sizeof(req))) {
        return "the server closed the connection before importing the device";
    }
    if (((req[2] << 8) | req[3]) != kOpReqImport) {
        return "unexpected request from the server";
    }

    std::vector<uint8_t> reply;
    put16(reply, kVersion);
    put16(reply, kOpRepImport);
    put32(reply, 0);
    putBytes(reply, info.path, 256);
    putBytes(reply, info.busid, 32);
    put32(reply, info.busnum);
    put32(reply, info.devnum);
    put32(reply, info.speed);
    put16(reply, info.idVendor);
    put16(reply, info.idProduct);
    put16(reply, info.bcdDevice);
    reply.push_back(info.bDeviceClass);
    reply.push_back(info.bDeviceSubClass);
    reply.push_back(info.bDeviceProtocol);
    reply.push_back(info.bConfigurationValue);
    reply.push_back(info.bNumConfigurations);
    reply.push_back(info.bNumInterfaces);

    if (!sslWriteAll(ssl, reply.data(), reply.size())) {
        return "sending the device description failed";
    }
    return {};
}

std::string Exporter::serve(SSL *ssl, int fd)
{
    std::vector<uint8_t> in;
    std::vector<uint8_t> out;
    uint8_t buf[16 * 1024];

    auto sendCompletion = [&](const Completion &c) {
        out.clear();
        put32(out, kRetSubmit);
        put32(out, c.seqnum);
        put32(out, 0);  // devid
        put32(out, 0);  // direction
        put32(out, 0);  // ep
        put32(out, (uint32_t)c.status);
        put32(out, c.in ? (uint32_t)c.data.size() : c.actualLength);
        put32(out, 0);           // start_frame
        put32(out, 0xffffffff);  // number_of_packets: not isochronous
        put32(out, 0);           // error_count
        put32(out, 0);
        put32(out, 0);
        if (c.in) {
            out.insert(out.end(), c.data.begin(), c.data.end());
        }
        return sslWriteAll(ssl, out.data(), out.size());
    };

    auto sendUnlinkReply = [&](uint32_t seqnum, int32_t status) {
        out.clear();
        put32(out, kRetUnlink);
        put32(out, seqnum);
        put32(out, 0);
        put32(out, 0);
        put32(out, 0);
        put32(out, (uint32_t)status);
        out.resize(kHeaderSize, 0);
        return sslWriteAll(ssl, out.data(), out.size());
    };

    // Send every completion the backend has finished so far. The kernel must
    // see a request's RET_SUBMIT before the RET_UNLINK that says it already completed.
    auto flushCompletions = [&]() {
        std::deque<Completion> done;
        {
            std::lock_guard<std::mutex> lg(m_Shared->lock);
            done.swap(m_Shared->done);
        }
        for (auto &c : done) {
            if (!sendCompletion(c)) {
                return false;
            }
        }
        return true;
    };

    pollfd fds[2] = {{fd, POLLIN, 0}, {m_WakePipe[0], POLLIN, 0}};

    while (true) {
        if (!SSL_pending(ssl) && poll(fds, 2, 2) < 0 && errno != EINTR) {
            return std::string("poll: ") + strerror(errno);
        }

        if (fds[1].revents & POLLIN) {
            (void)!read(m_WakePipe[0], buf, sizeof(buf));
        }

        {
            std::lock_guard<std::mutex> lg(m_Shared->lock);
            if (m_Shared->stopping) {
                return {};
            }
        }
        if (!flushCompletions()) {
            return "the connection closed";
        }

        m_Backend->poll();

        if (SSL_pending(ssl) || (fds[0].revents & (POLLIN | POLLHUP | POLLERR))) {
            int n = SSL_read(ssl, buf, sizeof(buf));
            if (n <= 0) {
                // The server detached the device or went away
                return {};
            }
            in.insert(in.end(), buf, buf + n);
        }
        fds[0].revents = fds[1].revents = 0;

        // Handle every complete command in the buffer
        size_t offset = 0;
        while (in.size() - offset >= kHeaderSize) {
            const uint8_t *h = in.data() + offset;
            uint32_t command = get32(h);
            uint32_t seqnum = get32(h + 4);
            bool dirIn = get32(h + 12) == 1;
            uint32_t ep = get32(h + 16);

            if (command == kCmdSubmit) {
                uint32_t length = get32(h + 24);
                uint32_t packets = get32(h + 32);
                size_t payload = dirIn ? 0 : length;
                if (packets != 0 && packets != 0xffffffff) {
                    // Isochronous descriptors follow the payload
                    payload += 16 * (size_t)packets;
                }
                if (in.size() - offset < kHeaderSize + payload) {
                    break;
                }

                if (packets != 0 && packets != 0xffffffff) {
                    // Isochronous transfers (audio, webcams) aren't supported yet
                    Completion c;
                    c.seqnum = seqnum;
                    c.in = dirIn;
                    c.status = -EOPNOTSUPP;
                    if (!sendCompletion(c)) {
                        return "the connection closed";
                    }
                } else {
                    Urb urb;
                    urb.seqnum = seqnum;
                    urb.in = dirIn;
                    urb.endpoint = ep & 0x0f;
                    memcpy(urb.setup, h + 40, 8);
                    if (dirIn) {
                        urb.data.resize(length);
                    } else {
                        urb.data.assign(h + kHeaderSize, h + kHeaderSize + length);
                    }
                    m_Backend->submit(std::move(urb));
                }
                offset += kHeaderSize + payload;
            } else if (command == kCmdUnlink) {
                uint32_t target = get32(h + 20);
                bool cancelled = m_Backend->unlink(target);
                if (!flushCompletions() || !sendUnlinkReply(seqnum, cancelled ? -ECONNRESET : 0)) {
                    return "the connection closed";
                }
                offset += kHeaderSize;
            } else {
                return "unknown USB/IP command " + std::to_string(command);
            }
        }
        in.erase(in.begin(), in.begin() + offset);
    }
}

}  // namespace usbip
