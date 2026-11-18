#include "backend.h"

#include <QClipboard>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>
#include <QUuid>
#include <csignal>
#include <sys/prctl.h>

namespace {
// A destination that cannot keep up would otherwise buffer the whole stream in
// memory, so it is dropped and retried instead.
constexpr qint64 kMaxBacklog = 32 * 1024 * 1024;
constexpr int kRetryMs = 5000;
constexpr int kIngestPort = 1935;

// An ffmpeg that outlives the app would keep holding the ingest port and keep
// sending to the destinations, so each child is told to die with its parent,
// even when the app is killed or crashes and never gets to clean up.
void dieWithParent(QProcess *process) {
    process->setChildProcessModifier([] { prctl(PR_SET_PDEATHSIG, SIGKILL); });
}
}

Backend::Backend(const QString &configFile, const QString &ffmpeg, const QString &secretTool, QObject *parent)
    : QAbstractListModel(parent),
      m_configFile(configFile.isEmpty() ? QDir::homePath() + "/.config/stream-all/outputs.json" : configFile),
      m_ffmpeg(ffmpeg.isEmpty() ? QStandardPaths::findExecutable("ffmpeg") : ffmpeg),
      m_secretTool(secretTool.isEmpty() ? QStandardPaths::findExecutable("secret-tool") : secretTool) {
    load();
    // The key OBS sends with is made up the first time the app runs, so
    // nobody else on the network can guess it, and kept from then on.
    if (m_ingestKey.isEmpty()) {
        m_ingestKey = newIngestKey();
        save();
    }
    if (m_outputs.isEmpty()) {
        Output blank;
        blank.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        m_outputs.append(blank);
    }
}

Backend::~Backend() {
    stopIngest();
    for (int row = 0; row < m_outputs.size(); ++row)
        stopOutput(row);
}

int Backend::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_outputs.size();
}

QVariant Backend::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_outputs.size())
        return {};
    const Output &o = m_outputs.at(index.row());
    switch (role) {
    case ServerRole: return o.server;
    case StreamKeyRole: return o.key;
    case ActiveRole: return o.active;
    case StatusRole: return o.status;
    case MessageRole: return o.message;
    case PlatformRole: return platformFor(o.server);
    case DetailsRole: return o.details;
    }
    return {};
}

QHash<int, QByteArray> Backend::roleNames() const {
    return {{ServerRole, "server"}, {StreamKeyRole, "streamKey"}, {ActiveRole, "active"},
            {StatusRole, "status"}, {MessageRole, "message"}, {PlatformRole, "platform"},
            {DetailsRole, "details"}};
}

QString Backend::ingestUrl() const {
    return QStringLiteral("rtmp://localhost:%1/live").arg(kIngestPort);
}

QString Backend::platformFor(const QString &server) {
    const QString s = server.toLower();
    if (s.contains("youtube"))
        return QStringLiteral("YouTube");
    if (s.contains("twitch"))
        return QStringLiteral("Twitch");
    if (s.contains("rumble") || s.contains("rmbl"))
        return QStringLiteral("Rumble");
    if (s.contains("kick"))
        return QStringLiteral("Kick");
    if (s.contains("facebook") || s.contains("fb.com"))
        return QStringLiteral("Facebook");
    return {};
}

QString Backend::outputUrl(const QString &server, const QString &key) {
    QString base = server.trimmed();
    while (base.endsWith('/'))
        base.chop(1);
    return key.trimmed().isEmpty() ? base : base + "/" + key.trimmed();
}

void Backend::copy(const QString &text) {
    QGuiApplication::clipboard()->setText(text);
}

// ---- persistence ----

void Backend::load() {
    QFile file(m_configFile);
    if (!file.open(QIODevice::ReadOnly))
        return;
    bool migrated = false, rewrite = false;
    const QJsonObject root = QJsonDocument::fromJson(file.readAll()).object();
    // Only letters, digits, - and _, since it goes into ffmpeg's URL; any
    // other value is replaced by a fresh key.
    static const QRegularExpression safeKey("^[A-Za-z0-9_-]{1,64}$");
    const QString key = root.value("ingestKey").toString();
    if (safeKey.match(key).hasMatch())
        m_ingestKey = key;
    const auto rows = root.value("outputs").toArray();
    for (const auto &value : rows) {
        const QJsonObject object = value.toObject();
        Output o;
        o.id = object.value("id").toString();
        if (o.id.isEmpty()) {
            o.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
            rewrite = true;
        }
        o.server = object.value("server").toString();
        o.active = object.value("active").toBool(true);
        o.status = !o.active ? "off" : o.server.trimmed().isEmpty() ? "empty" : "waiting";

        // Files from before the keyring held the key itself: move it over.
        const QString legacy = object.value("key").toString();
        if (!legacy.isEmpty()) {
            o.key = legacy;
            o.legacyKey = true;
            if (storeKey(o)) {
                o.legacyKey = false;
                migrated = true;
            }
        } else {
            loadKey(o);
        }
        m_outputs.append(o);
    }
    // Rewritten only once the keys are safely in the keyring, so a failed
    // migration never loses one.
    if (migrated || rewrite)
        save();
}

// Written beside the target and renamed, and readable only by the user. It
// holds no stream keys, apart from any still waiting to reach the keyring.
void Backend::save() const {
    QJsonArray rows;
    for (const Output &o : m_outputs) {
        QJsonObject row{{"id", o.id}, {"server", o.server}, {"active", o.active}};
        if (o.legacyKey)
            row.insert("key", o.key);
        rows.append(row);
    }
    QDir().mkpath(QFileInfo(m_configFile).absolutePath());
    QSaveFile file(m_configFile);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning("Could not save %s", qPrintable(m_configFile));
        return;
    }
    file.write(QJsonDocument(QJsonObject{{"ingestKey", m_ingestKey}, {"outputs", rows}}).toJson());
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    file.commit();
}

// ---- keyring ----

Backend::SecretResult Backend::runSecret(const QStringList &args, const QByteArray &input, QByteArray *output) const {
    if (m_secretTool.isEmpty())
        return SecretUnavailable;
    QProcess process;
    process.start(m_secretTool, args);
    if (!process.waitForStarted(3000))
        return SecretUnavailable;
    // The secret goes in on stdin, never on the command line where other
    // users' `ps` could read it.
    process.write(input);
    process.closeWriteChannel();
    // A locked keyring may be showing an unlock prompt, so allow time for it.
    if (!process.waitForFinished(30000)) {
        process.kill();
        process.waitForFinished(1000);
        return SecretUnavailable;
    }
    if (process.exitStatus() != QProcess::NormalExit)
        return SecretUnavailable;
    if (process.exitCode() == 0) {
        if (output)
            *output = process.readAllStandardOutput();
        return SecretOk;
    }
    // secret-tool exits 1 without a word when there is simply no such entry,
    // and with a message when the keyring itself is the problem.
    return process.readAllStandardError().trimmed().isEmpty() ? SecretMissing : SecretUnavailable;
}

void Backend::setKeyringError(const QString &message) {
    if (m_keyringError == message)
        return;
    m_keyringError = message;
    emit keyringErrorChanged();
}

bool Backend::storeKey(const Output &output) {
    if (output.key.isEmpty()) {
        clearKey(output);
        return true;
    }
    const auto result = runSecret({"store", "--label=Stream All output key", "application", "stream-all",
                                   "output", output.id},
                                  output.key.toUtf8());
    if (result == SecretOk)
        return true;
    setKeyringError(m_secretTool.isEmpty()
                        ? tr("secret-tool was not found. Install libsecret so stream keys can be stored encrypted.")
                        : tr("The keyring is not available, so stream keys cannot be saved. Unlock it or start gnome-keyring."));
    return false;
}

void Backend::clearKey(const Output &output) {
    runSecret({"clear", "application", "stream-all", "output", output.id}, {});
}

void Backend::loadKey(Output &output) {
    QByteArray key;
    const auto result = runSecret({"lookup", "application", "stream-all", "output", output.id}, {}, &key);
    if (result == SecretOk)
        output.key = QString::fromUtf8(key);
    else if (result == SecretUnavailable)
        setKeyringError(m_secretTool.isEmpty()
                            ? tr("secret-tool was not found. Install libsecret so stream keys can be stored encrypted.")
                            : tr("The keyring is not available, so stream keys cannot be read. Unlock it or start gnome-keyring."));
}

// ---- helpers ----

int Backend::rowOfId(const QString &id) const {
    for (int i = 0; i < m_outputs.size(); ++i)
        if (m_outputs.at(i).id == id)
            return i;
    return -1;
}

int Backend::rowOfProcess(QProcess *process) const {
    for (int i = 0; i < m_outputs.size(); ++i)
        if (m_outputs.at(i).process == process)
            return i;
    return -1;
}

void Backend::setStatus(int row, const QString &status, const QString &message) {
    Output &o = m_outputs[row];
    if (o.status == status && o.message == message)
        return;
    o.status = status;
    o.message = message;
    if (status != "error")
        o.details.clear();
    emit dataChanged(index(row), index(row), {StatusRole, MessageRole, DetailsRole});
}

void Backend::setLive(bool live) {
    if (m_live == live)
        return;
    m_live = live;
    emit liveChanged();
}

void Backend::setIngestError(const QString &message) {
    if (m_ingestError == message)
        return;
    m_ingestError = message;
    emit ingestErrorChanged();
}

// ffmpeg echoes the URL, and with it the stream key, in some errors.
QString Backend::redact(const QString &text, const Output &output) const {
    QString out = text;
    if (output.key.trimmed().size() >= 4)
        out.replace(output.key.trimmed(), QStringLiteral("***"));
    return out.trimmed();
}

// ---- model edits ----

void Backend::addOutput() {
    beginInsertRows({}, m_outputs.size(), m_outputs.size());
    Output o;
    o.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_outputs.append(o);
    endInsertRows();
    save();
}

void Backend::removeOutput(int row) {
    if (row < 0 || row >= m_outputs.size())
        return;
    stopOutput(row);
    clearKey(m_outputs.at(row));
    beginRemoveRows({}, row, row);
    m_outputs.removeAt(row);
    endRemoveRows();
    save();
}

void Backend::setServer(int row, const QString &server) {
    if (row < 0 || row >= m_outputs.size() || m_outputs.at(row).server == server.trimmed())
        return;
    m_outputs[row].server = server.trimmed();
    emit dataChanged(index(row), index(row), {ServerRole, PlatformRole});
    save();
    stopOutput(row);
    startOutput(row);
}

void Backend::setStreamKey(int row, const QString &key) {
    if (row < 0 || row >= m_outputs.size() || m_outputs.at(row).key == key.trimmed())
        return;
    m_outputs[row].key = key.trimmed();
    emit dataChanged(index(row), index(row), {StreamKeyRole});
    // Whatever happens to the keyring, the key no longer belongs in the file.
    if (storeKey(m_outputs.at(row))) {
        m_outputs[row].legacyKey = false;
        setKeyringError({});
    }
    save();
    stopOutput(row);
    startOutput(row);
}

void Backend::setActive(int row, bool active) {
    if (row < 0 || row >= m_outputs.size() || m_outputs.at(row).active == active)
        return;
    m_outputs[row].active = active;
    emit dataChanged(index(row), index(row), {ActiveRole});
    save();
    stopOutput(row);
    startOutput(row);
}

// ---- ingest: OBS to ffmpeg to us ----

QString Backend::newIngestKey() {
    static const QString alphabet = QStringLiteral("abcdefghijklmnopqrstuvwxyz0123456789");
    QString key;
    for (int i = 0; i < 24; ++i)
        key.append(alphabet.at(QRandomGenerator::system()->bounded(alphabet.size())));
    return key;
}

void Backend::rotateIngestKey() {
    m_ingestKey = newIngestKey();
    save();
    emit ingestKeyChanged();
    // ffmpeg was started with the old key, so it starts again with the new one.
    if (m_ingest) {
        stopIngest();
        startIngest();
    }
}

void Backend::setListening(bool on) {
    if (on == m_listening)
        return;
    if (on && m_ffmpeg.isEmpty()) {
        setIngestError(tr("ffmpeg was not found. Install it with: omarchy-pkg-add ffmpeg"));
        return;
    }
    m_listening = on;
    setIngestError({});
    if (on)
        startIngest();
    else
        stopIngest();
    emit listeningChanged();
}

void Backend::startIngest() {
    if (!m_listening || m_ingest)
        return;
    m_ingestLog.clear();
    m_ingest = new QProcess(this);
    dieWithParent(m_ingest);
    m_ingest->setProgram(m_ffmpeg);
    // Copying the packets keeps this cheap: nothing is re-encoded, so every
    // output gets exactly what OBS sends.
    m_ingest->setArguments({"-hide_banner", "-loglevel", "error", "-listen", "1", "-i",
                            QStringLiteral("rtmp://0.0.0.0:%1/live/%2").arg(kIngestPort).arg(ingestKey()),
                            "-c", "copy", "-f", "mpegts", "pipe:1"});
    connect(m_ingest, &QProcess::readyReadStandardOutput, this, &Backend::onIngestData);
    connect(m_ingest, &QProcess::readyReadStandardError, this,
            [this] { m_ingestLog += QString::fromUtf8(m_ingest->readAllStandardError()); });
    connect(m_ingest, &QProcess::finished, this, &Backend::onIngestFinished);
    connect(m_ingest, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_ingestLog = tr("Could not start ffmpeg");
            onIngestFinished();
        }
    });
    m_ingest->start();
}

void Backend::stopIngest() {
    if (m_ingest) {
        QProcess *p = m_ingest;
        m_ingest = nullptr;
        p->disconnect(this);
        p->kill();
        p->waitForFinished(500);
        p->deleteLater();
    }
    setLive(false);
    for (int row = 0; row < m_outputs.size(); ++row) {
        stopOutput(row);
        settleOutput(row);
    }
}

void Backend::onIngestData() {
    if (!m_ingest)
        return;
    const QByteArray data = m_ingest->readAllStandardOutput();
    if (!m_live) {
        setLive(true);
        setIngestError({});
        for (int row = 0; row < m_outputs.size(); ++row)
            startOutput(row);
    }
    for (Output &o : m_outputs) {
        if (!o.process)
            continue;
        if (o.process->bytesToWrite() > kMaxBacklog) {
            o.process->kill();
            continue;
        }
        o.process->write(data);
    }
}

void Backend::onIngestFinished() {
    if (!m_ingest)
        return;
    QProcess *p = m_ingest;
    m_ingest = nullptr;
    p->disconnect(this);
    p->deleteLater();

    // OBS stopping is normal and not worth a message; never having heard from
    // OBS means ffmpeg itself failed, usually because the port is taken.
    const bool wasLive = m_live;
    if (!wasLive && !m_ingestLog.trimmed().isEmpty())
        setIngestError(m_ingestLog.trimmed().split('\n').last());
    setLive(false);
    for (int row = 0; row < m_outputs.size(); ++row)
        endOutput(row);

    if (m_listening)
        QTimer::singleShot(wasLive ? 300 : 2000, this, &Backend::startIngest);
}

QString Backend::explainFailure(const QStringList &lines) {
    const QString all = lines.join('\n');
    // ffmpeg's last lines are only "Error opening output file"; the reason is
    // printed just above them, so match on that.
    const auto host = QRegularExpression("Failed to resolve hostname ([^:\\s]+)").match(all);
    if (host.hasMatch())
        return tr("Can't find the server %1. Check the address and your connection.").arg(host.captured(1));
    if (all.contains("Connection refused"))
        return tr("The server refused the connection. Check the address and the port.");
    if (all.contains("timed out") || all.contains("Network is unreachable") || all.contains("No route to host"))
        return tr("The server did not answer. Check the address and your connection.");
    if (all.contains("Protocol not found") || all.contains("TLS") || all.contains("SSL"))
        return tr("The secure connection (rtmps://) failed. Check the address, or try rtmp://.");
    if (all.contains("Input/output error") || all.contains("Server error") || all.contains("Broken pipe")
        || all.contains("Connection reset") || all.contains("End of file"))
        return tr("The platform closed the connection. Check the stream key, and that the stream is ready on the platform.");
    return lines.isEmpty() ? QString() : lines.last();
}

// ---- outputs: us to ffmpeg to each destination ----

void Backend::settleOutput(int row) {
    const Output &o = m_outputs.at(row);
    if (o.process)
        return;
    setStatus(row, !o.active ? "off" : o.server.trimmed().isEmpty() ? "empty" : "waiting");
}

void Backend::startOutput(int row) {
    Output &o = m_outputs[row];
    if (o.process)
        return;
    if (!m_live || !o.active || o.server.trimmed().isEmpty()) {
        settleOutput(row);
        return;
    }
    const QString url = outputUrl(o.server, o.key);
    if (!url.startsWith("rtmp://") && !url.startsWith("rtmps://")) {
        setStatus(row, "error", tr("The server must start with rtmp:// or rtmps://"));
        return;
    }

    auto *p = new QProcess(this);
    dieWithParent(p);
    p->setProgram(m_ffmpeg);
    // -stats keeps printing progress at this log level; a progress line means
    // the destination accepted the stream. ffmpeg would otherwise probe the
    // pipe for five seconds before connecting, which is a long wait for a
    // live stream; one second is plenty for a feed that already carries its
    // codec headers.
    p->setArguments({"-hide_banner", "-loglevel", "error", "-stats",
                     "-analyzeduration", "1000000", "-probesize", "1000000",
                     "-f", "mpegts", "-i", "pipe:0", "-c", "copy", "-f", "flv", url});
    connect(p, &QProcess::readyReadStandardError, this, [this, p] { onOutputStderr(p); });
    connect(p, &QProcess::finished, this, [this, p](int code) { onOutputFinished(p, code); });
    connect(p, &QProcess::errorOccurred, this, [this, p](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            p->setProperty("errLines", QStringList{tr("Could not start ffmpeg")});
            onOutputFinished(p, -1);
        }
    });
    o.process = p;
    // A retry keeps showing why the last attempt failed, so the explanation
    // does not vanish for a second and a half out of every six; it goes when
    // the output goes live, or is edited or switched off.
    if (o.status != "error")
        setStatus(row, "starting");
    p->start();
}

// Immediate: for edits, removal, and shutdown.
void Backend::stopOutput(int row) {
    Output &o = m_outputs[row];
    if (!o.process)
        return;
    QProcess *p = o.process;
    o.process = nullptr;
    p->disconnect(this);
    p->kill();
    p->waitForFinished(500);
    p->deleteLater();
    settleOutput(row);
}

// Graceful: closes the input so ffmpeg finishes the FLV and disconnects
// cleanly, with a kill as the backstop.
void Backend::endOutput(int row) {
    Output &o = m_outputs[row];
    if (!o.process) {
        settleOutput(row);
        return;
    }
    QProcess *p = o.process;
    p->closeWriteChannel();
    QTimer::singleShot(3000, p, [p] {
        if (p->state() != QProcess::NotRunning)
            p->kill();
    });
}

void Backend::onOutputStderr(QProcess *p) {
    const int row = rowOfProcess(p);
    if (row < 0)
        return;
    const QString text = QString::fromUtf8(p->readAllStandardError());
    for (const QString &line : text.split(QRegularExpression("[\r\n]"), Qt::SkipEmptyParts)) {
        if (line.contains("frame=") || line.contains("size=") || line.contains("time="))
            setStatus(row, "live");
        else {
            // Keep the last few lines without ffmpeg's "[rtmp @ 0x…]" prefix.
            static const QRegularExpression prefix(R"(^\[[^\]]*@ 0x[0-9a-f]+\]\s*)");
            QStringList lines = p->property("errLines").toStringList();
            lines << redact(line, m_outputs.at(row)).remove(prefix);
            while (lines.size() > 12)
                lines.removeFirst();
            p->setProperty("errLines", lines);
        }
    }
}

void Backend::onOutputFinished(QProcess *p, int code) {
    const int row = rowOfProcess(p);
    if (row < 0)
        return;
    Output &o = m_outputs[row];
    o.process = nullptr;
    p->deleteLater();

    if (!m_live || !o.active) {
        settleOutput(row);
        return;
    }
    // OBS reconnected before this output finished winding down.
    if (code == 0) {
        startOutput(row);
        return;
    }
    const QStringList lines = p->property("errLines").toStringList();
    o.details = lines.join('\n');
    const QString message = explainFailure(lines);
    setStatus(row, "error", message.isEmpty() ? tr("Stopped unexpectedly (exit code %1)").arg(code) : message);

    const QString id = o.id;
    QTimer::singleShot(kRetryMs, this, [this, id] {
        const int r = rowOfId(id);
        if (r >= 0)
            startOutput(r);
    });
}
