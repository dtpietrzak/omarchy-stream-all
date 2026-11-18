#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QProcess>

// The relay. One ffmpeg listens for OBS and writes MPEG-TS to its stdout; this
// object copies those bytes into one ffmpeg per output, so outputs can be
// added, edited, and removed while live without touching the others. It is
// also the list model behind the output rows.
class Backend : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool listening READ listening NOTIFY listeningChanged)
    Q_PROPERTY(bool live READ live NOTIFY liveChanged)
    Q_PROPERTY(QString ingestUrl READ ingestUrl CONSTANT)
    Q_PROPERTY(QString ingestKey READ ingestKey NOTIFY ingestKeyChanged)
    Q_PROPERTY(QString ingestError READ ingestError NOTIFY ingestErrorChanged)
    Q_PROPERTY(QString keyringError READ keyringError NOTIFY keyringErrorChanged)

public:
    enum Role { ServerRole = Qt::UserRole + 1, StreamKeyRole, ActiveRole, StatusRole, MessageRole, PlatformRole, DetailsRole };

    explicit Backend(const QString &configFile = {}, const QString &ffmpeg = {}, const QString &secretTool = {},
                     QObject *parent = nullptr);
    ~Backend() override;

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool listening() const { return m_listening; }
    bool live() const { return m_live; }
    QString ingestUrl() const;
    QString ingestKey() const { return m_ingestKey; }
    QString ingestError() const { return m_ingestError; }
    QString keyringError() const { return m_keyringError; }

    Q_INVOKABLE void setListening(bool on);
    Q_INVOKABLE void addOutput();
    Q_INVOKABLE void removeOutput(int row);
    Q_INVOKABLE void setServer(int row, const QString &server);
    Q_INVOKABLE void setStreamKey(int row, const QString &key);
    Q_INVOKABLE void setActive(int row, bool active);
    Q_INVOKABLE void copy(const QString &text);
    // A fresh key for OBS to use. If OBS is sending, that stream ends, since
    // OBS still has the old key.
    Q_INVOKABLE void rotateIngestKey();

    // Random letters and digits, safe to put in an RTMP URL.
    static QString newIngestKey();

    static QString platformFor(const QString &server);
    static QString outputUrl(const QString &server, const QString &key);
    // Turns the lines ffmpeg printed before giving up into a sentence that says
    // what to check; unknown failures fall back to ffmpeg's own last line.
    static QString explainFailure(const QStringList &lines);

signals:
    void listeningChanged();
    void liveChanged();
    void ingestErrorChanged();
    void ingestKeyChanged();
    void keyringErrorChanged();

private:
    struct Output {
        QString id, server, key;
        bool active = true;
        // A key read from a config file that still held it in plaintext and
        // has not reached the keyring yet; it stays in the file until it has.
        bool legacyKey = false;
        QString status = QStringLiteral("empty"), message, details;
        QProcess *process = nullptr;
    };

    void load();
    void save() const;
    int rowOfId(const QString &id) const;
    int rowOfProcess(QProcess *process) const;
    void setStatus(int row, const QString &status, const QString &message = {});
    void setLive(bool live);
    void setIngestError(const QString &message);
    void setKeyringError(const QString &message);

    // Stream keys live in the desktop keyring (Secret Service, through
    // secret-tool), one entry per output, so they are encrypted at rest and
    // never in the config file.
    enum SecretResult { SecretOk, SecretMissing, SecretUnavailable };
    SecretResult runSecret(const QStringList &args, const QByteArray &input, QByteArray *output = nullptr) const;
    bool storeKey(const Output &output);
    void clearKey(const Output &output);
    void loadKey(Output &output);
    QString redact(const QString &text, const Output &output) const;

    void startIngest();
    void stopIngest();
    void onIngestData();
    void onIngestFinished();

    void startOutput(int row);
    void stopOutput(int row);
    void endOutput(int row);
    void settleOutput(int row);
    void onOutputStderr(QProcess *process);
    void onOutputFinished(QProcess *process, int code);

    QString m_configFile, m_ffmpeg, m_secretTool, m_ingestError, m_ingestLog, m_keyringError, m_ingestKey;
    QList<Output> m_outputs;
    QProcess *m_ingest = nullptr;
    bool m_listening = false, m_live = false;
};
