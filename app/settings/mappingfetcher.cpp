#include "mappingfetcher.h"
#include "path.h"

#include <QNetworkReply>

MappingFetcher::MappingFetcher(QObject *parent) :
    QObject(parent)
{
    m_Nam = new QNetworkAccessManager(this);

    // Never communicate over HTTP
    m_Nam->setStrictTransportSecurityEnabled(true);

    // Allow HTTP redirects
    m_Nam->setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);

    connect(m_Nam, &QNetworkAccessManager::finished,
            this, &MappingFetcher::handleMappingListFetched);
}

void MappingFetcher::start()
{
    // Upstream downloaded fresh gamepad mappings from the Moonlight project's
    // servers here. Stand-In contacts no third-party servers; it uses the
    // SDL_GameControllerDB mappings bundled with the app.
}

void MappingFetcher::handleMappingListFetched(QNetworkReply* reply)
{
    Q_ASSERT(reply->isFinished());

    // Delete the QNetworkAccessManager to free resources and
    // prevent the bearer plugin from polling in the background.
    m_Nam->deleteLater();
    m_Nam = nullptr;

    if (reply->error() == QNetworkReply::NoError) {
        // Queue the reply for deletion
        reply->deleteLater();

        // If we get a 304 back, Qt will happily just tell us our request was
        // successful and let us try to write our empty response to disk. Check
        // the status code directly to prevent this.
        if (reply->attribute(QNetworkRequest::HttpStatusCodeAttribute) == 304) {
            qInfo() << "Gamepad mappings are up to date";
        }
        else {
            // Update the cached data on disk for next call to applyMappings()
            QByteArray data = reply->readAll();
            if (!data.isEmpty()) {
                Path::writeCacheFile("gamecontrollerdb.txt", data);
            }

            qInfo() << "Downloaded updated gamepad mappings";
        }
    }
    else {
        qWarning() << "Failed to download updated gamepad mappings:" << reply->error();
        reply->deleteLater();
    }
}
