#include "usbdevicemodel.h"

#ifdef HAVE_USB_FORWARDING
#include "backend/identitymanager.h"
#include "streaming/usb/usbipexport.h"
#endif

#include <QCoreApplication>
#include <QPointer>
#include <QSettings>
#include <QThread>

#include <atomic>
#include <thread>

#define SER_USB_TARGET "usb/target"
#define SER_USB_FORWARD "usb/forward"

static const char* kTestBusid = "test-1";

// Forwarding threads still running, so quitting can wait for them to let go of their devices
static std::atomic<int> s_RunningExporters { 0 };

namespace usbip {
#ifndef HAVE_USB_FORWARDING
class Exporter
{
public:
    void stop() {}
};
#endif
}

static QString kindOf(const std::vector<uint8_t>& interfaceClasses, bool& canSend)
{
    auto has = [&](uint8_t c) {
        return std::find(interfaceClasses.begin(), interfaceClasses.end(), c) != interfaceClasses.end();
    };

    // Audio and video move data in isochronous transfers, which aren't forwarded yet
    canSend = !has(0x01) && !has(0x0e);

    if (has(0x0e)) return "video";
    if (has(0x01)) return "audio";
    if (has(0x03)) return "input";
    if (has(0x08)) return "storage";
    if (has(0xe0)) return "wireless";
    if (has(0x02) || has(0x0a)) return "network";
    return "other";
}

UsbDeviceModel::UsbDeviceModel(QObject* parent)
    : QAbstractListModel(parent)
{
    QSettings settings;
    m_TargetUuid = settings.value(SER_USB_TARGET).toString();

    // Remembered devices show up even while unplugged, so they can be switched off
    QVariantMap remembered = settings.value(SER_USB_FORWARD).toMap();
    for (auto it = remembered.begin(); it != remembered.end(); ++it) {
        m_Forwards.insert(it.key(), Forward());

        Device device;
        device.key = it.key();
        device.busid = it.key().section('@', 1);
        device.name = it.value().toString();
        device.present = false;
        m_Devices.append(device);
    }

    connect(&m_RefreshTimer, &QTimer::timeout, this, &UsbDeviceModel::refresh);
    connect(qApp, &QCoreApplication::aboutToQuit, this, &UsbDeviceModel::stopAll);
}

UsbDeviceModel::~UsbDeviceModel()
{
    stopAll();
}

void UsbDeviceModel::initialize(ComputerManager* computerManager)
{
    if (m_ComputerManager || !supported()) {
        return;
    }

    m_ComputerManager = computerManager;
    connect(m_ComputerManager, &ComputerManager::computerStateChanged,
            this, &UsbDeviceModel::handleComputerStateChanged);

    reloadTargets();
    refresh();
    m_RefreshTimer.start(3000);
}

bool UsbDeviceModel::supported() const
{
#ifdef HAVE_USB_FORWARDING
    return true;
#else
    return false;
#endif
}

void UsbDeviceModel::refresh()
{
#ifdef HAVE_USB_FORWARDING
    std::vector<usbip::DeviceInfo> found = usbip::listLocalDevices();
    found.push_back(usbip::makeTestController(kTestBusid)->info());

    QVector<Device> devices;
    bool permissionProblem = false;
    for (const usbip::DeviceInfo& info : found) {
        Device device;
        device.busid = QString::fromStdString(info.busid);
        device.key = QString::asprintf("%04x:%04x@", info.idVendor, info.idProduct) + device.busid;
        device.name = QString::fromStdString(info.name);
        device.accessible = info.accessible;
        device.kind = kindOf(info.interfaceClasses, device.canSend);

        QString ids = QString::asprintf("%04x:%04x", info.idVendor, info.idProduct);
        device.detail = info.manufacturer.empty() ? ids : QString::fromStdString(info.manufacturer) + " · " + ids;
        if (device.busid == kTestBusid) {
            device.kind = "test";
            device.detail = tr("Built in · a virtual gamepad for checking that forwarding works");
        }

        permissionProblem |= !device.accessible;
        devices.append(device);
    }

    // Remembered devices that aren't plugged in stay listed
    for (const Device& old : m_Devices) {
        bool stillHere = std::any_of(devices.begin(), devices.end(), [&](const Device& d) { return d.key == old.key; });
        if (!stillHere && m_Forwards.contains(old.key)) {
            Device gone = old;
            gone.present = false;
            devices.append(gone);
        }
    }

    // A device that was pulled out while being sent: stop and wait for it to come back
    for (auto it = m_Forwards.begin(); it != m_Forwards.end(); ++it) {
        int row = -1;
        for (int i = 0; i < devices.size(); i++) {
            if (devices[i].key == it.key()) {
                row = i;
            }
        }
        if (it->exporter && row >= 0 && !devices[row].present) {
            it->exporter->stop();
            it->exporter.reset();
            it->state = Waiting;
        }
    }

    // Update the list in place so it keeps its scroll position and focus
    for (int row = m_Devices.size() - 1; row >= 0; row--) {
        bool kept = std::any_of(devices.begin(), devices.end(), [&](const Device& d) { return d.key == m_Devices[row].key; });
        if (!kept) {
            beginRemoveRows(QModelIndex(), row, row);
            m_Devices.removeAt(row);
            endRemoveRows();
        }
    }
    for (const Device& device : devices) {
        int row = rowOf(device.key);
        if (row < 0) {
            beginInsertRows(QModelIndex(), m_Devices.size(), m_Devices.size());
            m_Devices.append(device);
            endInsertRows();
        }
        else {
            const Device& old = m_Devices[row];
            if (old.name != device.name || old.detail != device.detail || old.present != device.present ||
                old.accessible != device.accessible || old.kind != device.kind) {
                m_Devices[row] = device;
                emit dataChanged(index(row), index(row));
            }
        }
    }

    if (permissionProblem != m_PermissionProblem) {
        m_PermissionProblem = permissionProblem;
        emit permissionProblemChanged();
    }

    startDue();
#endif
}

void UsbDeviceModel::setForwarding(int row, bool on)
{
    if (row < 0 || row >= m_Devices.size()) {
        return;
    }

    const Device device = m_Devices[row];
    if (on == m_Forwards.contains(device.key)) {
        return;
    }

    if (on) {
        m_Forwards.insert(device.key, Forward());
        setRemembered(device.key, device.name, true);
        changed(device.key);
        startDue();
    }
    else {
        Forward forward = m_Forwards.take(device.key);
        if (forward.exporter) {
            forward.exporter->stop();
        }
        setRemembered(device.key, device.name, false);

        if (!device.present) {
            beginRemoveRows(QModelIndex(), row, row);
            m_Devices.removeAt(row);
            endRemoveRows();
        }
        else {
            changed(device.key);
        }
    }
}

void UsbDeviceModel::setRemembered(const QString& key, const QString& name, bool on)
{
    QSettings settings;
    QVariantMap remembered = settings.value(SER_USB_FORWARD).toMap();
    if (on) {
        remembered.insert(key, name);
    }
    else {
        remembered.remove(key);
    }
    settings.setValue(SER_USB_FORWARD, remembered);
}

void UsbDeviceModel::startDue()
{
    if (!target() || !m_TargetOnline) {
        return;
    }

    for (auto it = m_Forwards.begin(); it != m_Forwards.end(); ++it) {
        bool due = it->state == Waiting ||
                   (it->state == Failed && it->sinceFailure.isValid() && it->sinceFailure.elapsed() > 10000);
        if (!due) {
            continue;
        }

        int row = rowOf(it.key());
        if (row >= 0 && m_Devices[row].present && m_Devices[row].accessible && m_Devices[row].canSend) {
            start(m_Devices[row]);
        }
    }
}

void UsbDeviceModel::start(const Device& device)
{
#ifdef HAVE_USB_FORWARDING
    Forward& forward = m_Forwards[device.key];

    usbip::ServerIdentity server;
    {
        NvComputer* computer = target();
        QReadLocker lock(&computer->lock);
        server.host = computer->activeAddress.address().toStdString();
        server.httpsPort = computer->activeHttpsPort;
        server.serverCertPem = computer->serverCert.toPem().toStdString();
    }
    server.clientCertPem = IdentityManager::get()->getCertificate().toStdString();
    server.clientKeyPem = IdentityManager::get()->getPrivateKey().toStdString();

    if (server.serverCertPem.empty()) {
        forward.state = Failed;
        forward.error = tr("pair with this PC again first");
        forward.sinceFailure.start();
        changed(device.key);
        return;
    }

    std::string error;
    auto backend = device.busid == kTestBusid ? usbip::makeTestController(kTestBusid)
                                              : usbip::openLocalDevice(device.busid.toStdString(), error);
    if (!backend) {
        forward.state = Failed;
        forward.error = QString::fromStdString(error);
        forward.sinceFailure.start();
        changed(device.key);
        return;
    }

    auto exporter = std::make_shared<usbip::Exporter>(server, std::move(backend));
    forward.exporter = exporter;
    forward.state = Connecting;
    forward.error.clear();
    changed(device.key);

    QPointer<UsbDeviceModel> self(this);
    QString key = device.key;
    usbip::Exporter* id = exporter.get();

    exporter->onAttached = [self, key, id]() {
        QMetaObject::invokeMethod(qApp, [self, key, id]() {
            if (self && self->m_Forwards.contains(key) && self->m_Forwards[key].exporter.get() == id) {
                self->m_Forwards[key].state = Sending;
                self->changed(key);
            }
        }, Qt::QueuedConnection);
    };

    s_RunningExporters++;
    std::thread([exporter, self, key, id]() {
        QString error = QString::fromStdString(exporter->run());
        QMetaObject::invokeMethod(qApp, [self, key, id, error]() {
            if (self && self->m_Forwards.contains(key) && self->m_Forwards[key].exporter.get() == id) {
                self->finished(key, error);
            }
        }, Qt::QueuedConnection);
        s_RunningExporters--;
    }).detach();
#else
    Q_UNUSED(device)
#endif
}

void UsbDeviceModel::finished(QString key, QString error)
{
    // Still switched on, so this end wasn't asked for: try again shortly
    Forward& forward = m_Forwards[key];
    forward.exporter.reset();
    forward.state = Failed;
    forward.error = error.isEmpty() ? tr("the PC ended the connection") : error;
    forward.sinceFailure.start();
    changed(key);
}

void UsbDeviceModel::stopAll()
{
    for (auto it = m_Forwards.begin(); it != m_Forwards.end(); ++it) {
        if (it->exporter) {
            it->exporter->stop();
            it->exporter.reset();
            it->state = Waiting;
        }
    }

    // Give the devices back to this machine before the process goes away
    for (int i = 0; i < 100 && s_RunningExporters > 0; i++) {
        QThread::msleep(10);
    }
}

void UsbDeviceModel::handleComputerStateChanged(NvComputer*)
{
    reloadTargets();
    startDue();
}

void UsbDeviceModel::reloadTargets()
{
    QStringList uuids;
    QStringList names;
    for (NvComputer* computer : m_ComputerManager->getComputers()) {
        QReadLocker lock(&computer->lock);
        if (computer->pairState == NvComputer::PS_PAIRED) {
            uuids.append(computer->uuid);
            names.append(computer->name);
        }
    }

    // Default to the first paired PC until the user picks one
    if (!uuids.contains(m_TargetUuid) && !uuids.isEmpty()) {
        m_TargetUuid = uuids.first();
    }

    bool online = false;
    if (NvComputer* computer = target()) {
        QReadLocker lock(&computer->lock);
        online = computer->state == NvComputer::CS_ONLINE && !computer->activeAddress.isNull();
    }

    if (uuids != m_TargetUuids || names != m_TargetNames || online != m_TargetOnline) {
        m_TargetUuids = uuids;
        m_TargetNames = names;
        m_TargetOnline = online;
        emit targetsChanged();

        // Status lines name the PC and whether it's reachable
        if (!m_Devices.isEmpty()) {
            emit dataChanged(index(0), index(m_Devices.size() - 1), { StatusRole });
        }
    }
}

NvComputer* UsbDeviceModel::target() const
{
    if (!m_ComputerManager || m_TargetUuid.isEmpty()) {
        return nullptr;
    }
    for (NvComputer* computer : m_ComputerManager->getComputers()) {
        if (computer->uuid == m_TargetUuid) {
            return computer;
        }
    }
    return nullptr;
}

QStringList UsbDeviceModel::targets() const
{
    return m_TargetNames;
}

int UsbDeviceModel::targetIndex() const
{
    return m_TargetUuids.indexOf(m_TargetUuid);
}

void UsbDeviceModel::setTargetIndex(int targetIndex)
{
    if (targetIndex < 0 || targetIndex >= m_TargetUuids.size() || m_TargetUuids[targetIndex] == m_TargetUuid) {
        return;
    }

    m_TargetUuid = m_TargetUuids[targetIndex];
    QSettings().setValue(SER_USB_TARGET, m_TargetUuid);

    // Move everything that's being sent over to the new PC
    for (auto it = m_Forwards.begin(); it != m_Forwards.end(); ++it) {
        if (it->exporter) {
            it->exporter->stop();
            it->exporter.reset();
        }
        it->state = Waiting;
    }

    m_TargetOnline = false;
    reloadTargets();
    emit targetsChanged();
    if (!m_Devices.isEmpty()) {
        emit dataChanged(index(0), index(m_Devices.size() - 1));
    }
    startDue();
}

bool UsbDeviceModel::targetOnline() const
{
    return m_TargetOnline;
}

bool UsbDeviceModel::permissionProblem() const
{
    return m_PermissionProblem;
}

QString UsbDeviceModel::permissionFix() const
{
#ifdef USB_RULES_PATH
    return QString("pkexec sh -c 'install -m 644 %1 /etc/udev/rules.d/ && udevadm trigger'").arg(USB_RULES_PATH);
#else
    return QString();
#endif
}

int UsbDeviceModel::rowOf(const QString& key) const
{
    for (int i = 0; i < m_Devices.size(); i++) {
        if (m_Devices[i].key == key) {
            return i;
        }
    }
    return -1;
}

void UsbDeviceModel::changed(const QString& key)
{
    int row = rowOf(key);
    if (row >= 0) {
        emit dataChanged(index(row), index(row));
    }
}

int UsbDeviceModel::rowCount(const QModelIndex& parent) const
{
    Q_UNUSED(parent)
    return m_Devices.size();
}

QHash<int, QByteArray> UsbDeviceModel::roleNames() const
{
    return {
        { NameRole, "name" },
        { DetailRole, "detail" },
        { KindRole, "kind" },
        { ForwardingRole, "forwarding" },
        { StateRole, "state" },
        { StatusRole, "status" },
        { AccessibleRole, "accessible" },
        { CanSendRole, "canSend" },
    };
}

QVariant UsbDeviceModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() >= m_Devices.size()) {
        return QVariant();
    }

    const Device& device = m_Devices[index.row()];
    bool forwarding = m_Forwards.contains(device.key);
    State state = forwarding ? m_Forwards[device.key].state : Off;
    QString pc = targetIndex() >= 0 ? m_TargetNames[targetIndex()] : tr("the PC");

    switch (role) {
    case NameRole:
        return device.name;
    case DetailRole:
        return device.detail;
    case KindRole:
        return device.kind;
    case ForwardingRole:
        return forwarding;
    case StateRole:
        return state;
    case AccessibleRole:
        return device.accessible;
    case CanSendRole:
        return device.canSend && device.accessible;
    case StatusRole:
        if (!device.present) {
            return tr("Not plugged in · it'll be sent when it is");
        }
        if (!device.canSend) {
            return tr("Webcams and audio devices can't be sent yet");
        }
        if (!device.accessible) {
            return tr("This user isn't allowed to use this device yet (see the note above)");
        }
        switch (state) {
        case Off:
            if (device.kind == "input") {
                return tr("Already works through normal input. Send it only if %1 needs the device itself.").arg(pc);
            }
            if (device.kind == "wireless") {
                return tr("Bluetooth or Wi-Fi on this machine stops while it's sent");
            }
            return QString();
        case Waiting:
            return target() ? tr("Waiting for %1 to come online").arg(pc) : tr("Pair with a PC to send devices");
        case Connecting:
            return tr("Connecting to %1…").arg(pc);
        case Sending:
            return device.kind == "test" ? tr("Plugged into %1").arg(pc)
                                         : tr("Plugged into %1 · not usable here until you switch it off").arg(pc);
        case Failed:
            return tr("Couldn't send it: %1. Trying again…").arg(m_Forwards[device.key].error);
        }
    }

    return QVariant();
}
