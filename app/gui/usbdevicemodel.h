#pragma once

#include "backend/computermanager.h"

#include <QAbstractListModel>
#include <QElapsedTimer>
#include <QTimer>

#include <memory>

namespace usbip { class Exporter; }

// Stand-In: the USB devices on this machine and which of them are being sent
// to the big PC over USB/IP. Devices the user switches on are remembered and
// sent again whenever they're plugged in and the PC is online.
class UsbDeviceModel : public QAbstractListModel
{
    Q_OBJECT

    Q_PROPERTY(bool supported READ supported CONSTANT)
    Q_PROPERTY(QStringList targets READ targets NOTIFY targetsChanged)
    Q_PROPERTY(int targetIndex READ targetIndex WRITE setTargetIndex NOTIFY targetsChanged)
    Q_PROPERTY(bool targetOnline READ targetOnline NOTIFY targetsChanged)
    Q_PROPERTY(bool permissionProblem READ permissionProblem NOTIFY permissionProblemChanged)
    Q_PROPERTY(QString permissionFix READ permissionFix CONSTANT)

    enum Roles
    {
        NameRole = Qt::UserRole,
        DetailRole,
        KindRole,
        ForwardingRole,
        StateRole,
        StatusRole,
        AccessibleRole,
        CanSendRole,
    };

public:
    enum State
    {
        Off,
        Waiting,     // switched on, waiting for the device or the PC
        Connecting,
        Sending,
        Failed,
    };
    Q_ENUM(State)

    explicit UsbDeviceModel(QObject* parent = nullptr);
    ~UsbDeviceModel() override;

    Q_INVOKABLE void initialize(ComputerManager* computerManager);

    Q_INVOKABLE void refresh();

    Q_INVOKABLE void setForwarding(int row, bool on);

    QVariant data(const QModelIndex& index, int role) const override;
    int rowCount(const QModelIndex& parent) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool supported() const;
    QStringList targets() const;
    int targetIndex() const;
    void setTargetIndex(int index);
    bool targetOnline() const;
    bool permissionProblem() const;
    QString permissionFix() const;

signals:
    void targetsChanged();
    void permissionProblemChanged();

private slots:
    void handleComputerStateChanged(NvComputer* computer);
    void stopAll();

private:
    struct Device
    {
        QString key;     // what's remembered: vid:pid@busid
        QString busid;
        QString name;
        QString detail;
        QString kind;    // input, storage, audio, video, network, test, other
        bool accessible = true;
        bool present = true;
        bool canSend = true;  // false for isochronous devices until those are supported
    };

    struct Forward
    {
        std::shared_ptr<usbip::Exporter> exporter;
        State state = Waiting;
        QString error;
        QElapsedTimer sinceFailure;
    };

    void reloadTargets();
    NvComputer* target() const;
    void startDue();
    void start(const Device& device);
    void finished(QString key, QString error);
    void setRemembered(const QString& key, const QString& name, bool on);
    int rowOf(const QString& key) const;
    void changed(const QString& key);

    ComputerManager* m_ComputerManager = nullptr;
    QVector<Device> m_Devices;
    QMap<QString, Forward> m_Forwards;  // switched-on devices, by key
    QStringList m_TargetUuids;
    QStringList m_TargetNames;
    QString m_TargetUuid;
    bool m_TargetOnline = false;
    bool m_PermissionProblem = false;
    QTimer m_RefreshTimer;
};
