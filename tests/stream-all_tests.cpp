#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QtTest>

#include "backend.h"
#include "theme.h"
#include "translator.h"

class StreamAllTests : public QObject {
    Q_OBJECT

private slots:
    void detectsPlatforms()
    {
        QCOMPARE(Backend::platformFor("rtmp://a.rtmp.youtube.com/live2"), QString("YouTube"));
        QCOMPARE(Backend::platformFor("rtmp://live.twitch.tv/app"), QString("Twitch"));
        QCOMPARE(Backend::platformFor("rtmp://ls27.live.rmbl.ws/slot-1"), QString("Rumble"));
        QCOMPARE(Backend::platformFor("rtmp://example.com/live"), QString());
    }

    void joinsServerAndKey()
    {
        QCOMPARE(Backend::outputUrl("rtmp://a/live/", " key "), QString("rtmp://a/live/key"));
        QCOMPARE(Backend::outputUrl("rtmp://a/live", ""), QString("rtmp://a/live"));
    }

    void startsWithOneBlankRow()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("outputs.json"), "/bin/true", secrets(dir));
        QCOMPARE(backend.rowCount(), 1);
        QCOMPARE(backend.data(backend.index(0), Backend::StatusRole).toString(), QString("empty"));
    }

    void savesAndReloadsOutputsPrivately()
    {
        QTemporaryDir dir;
        const QString file = dir.filePath("outputs.json");
        {
            Backend backend(file, "/bin/true", secrets(dir));
            backend.setServer(0, " rtmp://live.twitch.tv/app ");
            backend.setStreamKey(0, "secret");
            backend.setActive(0, false);
            backend.addOutput();
        }
        QCOMPARE(QFile::permissions(file) & (QFile::ReadGroup | QFile::ReadOther), QFileDevice::Permissions());
        Backend again(file, "/bin/true", secrets(dir));
        QCOMPARE(again.rowCount(), 2);
        QCOMPARE(again.data(again.index(0), Backend::ServerRole).toString(), QString("rtmp://live.twitch.tv/app"));
        QCOMPARE(again.data(again.index(0), Backend::StreamKeyRole).toString(), QString("secret"));
        QCOMPARE(again.data(again.index(0), Backend::StatusRole).toString(), QString("off"));
    }

    void keysGoToTheKeyringNotTheFile()
    {
        QTemporaryDir dir;
        const QString file = dir.filePath("outputs.json");
        {
            Backend backend(file, "/bin/true", secrets(dir));
            backend.setServer(0, "rtmp://live.twitch.tv/app");
            backend.setStreamKey(0, "super-secret-key");
            QVERIFY(backend.keyringError().isEmpty());
        }
        QVERIFY(!readAll(file).contains("super-secret-key"));
        Backend again(file, "/bin/true", secrets(dir));
        QCOMPARE(again.data(again.index(0), Backend::StreamKeyRole).toString(), QString("super-secret-key"));
    }

    void migratesPlaintextKeysAndRewritesTheFile()
    {
        QTemporaryDir dir;
        const QString file = dir.filePath("outputs.json");
        write(file, "{\"outputs\":[{\"server\":\"rtmp://a/live\",\"key\":\"old-plaintext-key\",\"active\":true}]}");

        {
            Backend backend(file, "/bin/true", secrets(dir));
            QCOMPARE(backend.data(backend.index(0), Backend::StreamKeyRole).toString(), QString("old-plaintext-key"));
        }
        QVERIFY(!readAll(file).contains("old-plaintext-key"));
        Backend again(file, "/bin/true", secrets(dir));
        QCOMPARE(again.data(again.index(0), Backend::StreamKeyRole).toString(), QString("old-plaintext-key"));
    }

    void neverLosesAKeyWhenTheKeyringIsDown()
    {
        QTemporaryDir dir;
        const QString file = dir.filePath("outputs.json");
        write(file, "{\"outputs\":[{\"server\":\"rtmp://a/live\",\"key\":\"old-plaintext-key\",\"active\":true}]}");

        {
            Backend backend(file, "/bin/true", secrets(dir, true));
            QVERIFY(!backend.keyringError().isEmpty());
            QCOMPARE(backend.data(backend.index(0), Backend::StreamKeyRole).toString(), QString("old-plaintext-key"));
            backend.addOutput(); // saves the file again
        }
        // Still readable once the keyring is back, and then moved over.
        QVERIFY(readAll(file).contains("old-plaintext-key"));
        Backend recovered(file, "/bin/true", secrets(dir));
        QVERIFY(recovered.keyringError().isEmpty());
        QCOMPARE(recovered.data(recovered.index(0), Backend::StreamKeyRole).toString(), QString("old-plaintext-key"));
        QVERIFY(!readAll(file).contains("old-plaintext-key"));
    }

    void doesNotWriteNewKeysToDiskWhenTheKeyringIsDown()
    {
        QTemporaryDir dir;
        const QString file = dir.filePath("outputs.json");
        Backend backend(file, "/bin/true", secrets(dir, true));
        backend.setStreamKey(0, "brand-new-key");
        QVERIFY(!backend.keyringError().isEmpty());
        QVERIFY(!readAll(file).contains("brand-new-key"));
    }

    void removingAnOutputClearsItsKey()
    {
        QTemporaryDir dir;
        const QString file = dir.filePath("outputs.json");
        Backend backend(file, "/bin/true", secrets(dir));
        backend.setStreamKey(0, "to-be-removed");
        backend.addOutput();
        QVERIFY(QDir(dir.filePath("secrets")).entryList(QDir::Files).size() == 1);
        backend.removeOutput(0);
        QVERIFY(QDir(dir.filePath("secrets")).entryList(QDir::Files).isEmpty());
    }

    void explainsWhyAnOutputFailed()
    {
        // ffmpeg's own last lines say only "Error opening output file"; the
        // reason is above them.
        QVERIFY(Backend::explainFailure({"Failed to resolve hostname live.exmaple.tv: Name or service not known",
                                         "Error opening output file rtmp://live.exmaple.tv/app/***."})
                    .contains("live.exmaple.tv"));
        QVERIFY(Backend::explainFailure({"Connection to tcp://127.0.0.1:1999 failed: Connection refused",
                                         "Error opening output files: Connection refused"})
                    .contains("refused"));
        QVERIFY(Backend::explainFailure({"Error opening output rtmp://a/b/***: Input/output error"})
                    .contains("stream key"));
        QCOMPARE(Backend::explainFailure({"Something nobody has seen before"}), QString("Something nobody has seen before"));
        QVERIFY(Backend::explainFailure({}).isEmpty());
    }

    void showsTheExplanationAndKeepsTheDetailsWithoutTheKey()
    {
        QTemporaryDir dir;
        const QString fake = dir.filePath("ffmpeg");
        write(fake, "#!/bin/sh\n"
                    "case \"$*\" in\n"
                    "  *-listen*) while true; do printf 'x'; sleep 0.1; done ;;\n"
                    "  *) echo '[tcp @ 0x1] Failed to resolve hostname nowhere.invalid: nope' >&2\n"
                    "     echo '[out#0/flv @ 0x2] Error opening output rtmp://nowhere.invalid/live/topsecret99: x' >&2\n"
                    "     exit 1 ;;\n"
                    "esac\n");
        QFile::setPermissions(fake, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);

        Backend backend(dir.filePath("outputs.json"), fake, secrets(dir));
        backend.setServer(0, "rtmp://nowhere.invalid/live");
        backend.setStreamKey(0, "topsecret99");
        backend.setListening(true);
        const QModelIndex row = backend.index(0);
        QTRY_COMPARE_WITH_TIMEOUT(backend.data(row, Backend::StatusRole).toString(), QString("error"), 4000);
        QVERIFY(backend.data(row, Backend::MessageRole).toString().contains("nowhere.invalid"));
        const QString details = backend.data(row, Backend::DetailsRole).toString();
        QVERIFY(details.contains("Failed to resolve hostname"));
        QVERIFY(!details.contains("topsecret99"));
        QVERIFY(!details.contains("[tcp @"));

        // The retry five seconds later must not blank the explanation.
        QTest::qWait(5600);
        QCOMPARE(backend.data(row, Backend::StatusRole).toString(), QString("error"));
        QVERIFY(backend.data(row, Backend::MessageRole).toString().contains("nowhere.invalid"));
    }

    void removesOutputs()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("outputs.json"), "/bin/true", secrets(dir));
        backend.addOutput();
        backend.removeOutput(0);
        QCOMPARE(backend.rowCount(), 1);
    }

    void reportsMissingFfmpegInsteadOfListening()
    {
        QTemporaryDir dir;
        const QByteArray path = qgetenv("PATH");
        qputenv("PATH", "/nonexistent");
        Backend backend(dir.filePath("outputs.json"));
        qputenv("PATH", path);
        backend.setListening(true);
        QVERIFY(!backend.listening());
        QVERIFY(!backend.ingestError().isEmpty());
    }

    // The fake ffmpeg stands in for both roles: with -listen it behaves like an
    // OBS feed that never ends, otherwise like a destination that accepts it.
    void relaysToOutputsOnceLive()
    {
        QTemporaryDir dir;
        const QString fake = dir.filePath("ffmpeg");
        write(fake, "#!/bin/sh\n"
                    "case \"$*\" in\n"
                    "  *-listen*) while true; do printf 'x'; sleep 0.1; done ;;\n"
                    "  *) echo 'frame=1 size=1kB' >&2; cat > /dev/null ;;\n"
                    "esac\n");
        QFile::setPermissions(fake, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);

        Backend backend(dir.filePath("outputs.json"), fake, secrets(dir));
        backend.setServer(0, "rtmp://example.com/live");
        backend.setStreamKey(0, "abcd");
        backend.setListening(true);
        QTRY_VERIFY_WITH_TIMEOUT(backend.live(), 3000);
        QTRY_COMPARE_WITH_TIMEOUT(backend.data(backend.index(0), Backend::StatusRole).toString(), QString("live"), 3000);

        backend.setActive(0, false);
        QCOMPARE(backend.data(backend.index(0), Backend::StatusRole).toString(), QString("off"));
        backend.setListening(false);
        QVERIFY(!backend.live());
    }

    void rejectsServersThatAreNotRtmp()
    {
        QTemporaryDir dir;
        const QString fake = dir.filePath("ffmpeg");
        write(fake, "#!/bin/sh\nwhile true; do printf 'x'; sleep 0.1; done\n");
        QFile::setPermissions(fake, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);

        Backend backend(dir.filePath("outputs.json"), fake, secrets(dir));
        backend.setServer(0, "http://example.com");
        backend.setListening(true);
        QTRY_COMPARE_WITH_TIMEOUT(backend.data(backend.index(0), Backend::StatusRole).toString(), QString("error"), 3000);
    }

    void themeFallsBack()
    {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QString("black"));
    }

    void themeReadsAccent()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("theme");
        QFile colors(dir.path() + "/theme/colors.toml");
        QVERIFY(colors.open(QIODevice::WriteOnly));
        colors.write("accent = \"#112233\"\n");
        colors.close();

        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#112233"));
        QCOMPARE(theme.accentForeground(), QString("white"));
    }

    void themeFollowsHyprlandRounding()
    {
        QTemporaryDir dir;
        const QString response = dir.filePath("response.json"), command = dir.filePath("hyprctl");
        auto write = [](const QString &path, const QByteArray &data) {
            QFile file(path);
            return file.open(QIODevice::WriteOnly) && file.write(data) == data.size();
        };
        QVERIFY(write(command, "#!/bin/sh\ncat '" + response.toUtf8() + "'\n"));
        QVERIFY(QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        QVERIFY(write(response, "{\"int\":0}"));

        Theme theme(dir.path(), nullptr, command);
        QCOMPARE(theme.radius(), 0);
        QVERIFY(write(response, "{\"int\":6}"));
        QTRY_COMPARE(theme.radius(), 6);
    }

    void translatorFallsBackToEnglish()
    {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Save").isNull());
    }

    void translatorFollowsTheLanguageFile()
    {
        QTemporaryDir dir;
        write(dir.path() + "/language", "pt-BR\n");
        write(dir.path() + "/pt.json", R"({"Save": "Guardar", "Open": "Abrir"})");
        write(dir.path() + "/pt-BR.json", R"({"Save": "Salvar"})");

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("pt-BR"));
        QCOMPARE(translator.translate("Main", "Save"), QString("Salvar"));
        QCOMPARE(translator.translate("Main", "Open"), QString("Abrir"));
        QVERIFY(translator.translate("Main", "Quit").isNull());
    }

    void translatorPicksPluralForms()
    {
        QTemporaryDir dir;
        write(dir.path() + "/language", "ru\n");
        write(dir.path() + "/en.json", R"({"%n clips": {"one": "%n clip", "other": "%n clips"}})");
        write(dir.path() + "/ru.json", R"({"%n clips": {"one": "%n клип", "few": "%n клипа", "many": "%n клипов", "other": "%n клипа"}})");

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 21), QString("%n клип"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 22), QString("%n клипа"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 25), QString("%n клипов"));
        QCOMPARE(Translator::pluralCategory("ar", 11), QString("many"));
        QCOMPARE(Translator::pluralCategory("ja", 1), QString("other"));
    }

private:
    // A stand-in for secret-tool that keeps entries as files, so tests never
    // touch the real keyring. With broken set, it fails the way a missing
    // Secret Service does.
    static QString secrets(const QTemporaryDir &dir, bool broken = false)
    {
        const QString path = dir.filePath(broken ? "secret-tool-broken" : "secret-tool");
        if (QFile::exists(path))
            return path;
        write(path, broken ? QByteArray("#!/bin/sh\necho 'Cannot autolaunch D-Bus' >&2\nexit 1\n")
                           : QByteArray("#!/bin/sh\n"
                                        "store=\"$(dirname \"$0\")/secrets\"; mkdir -p \"$store\"\n"
                                        "cmd=\"$1\"; shift; id=\"\"\n"
                                        "while [ $# -gt 0 ]; do if [ \"$1\" = output ]; then id=\"$2\"; shift; fi; shift; done\n"
                                        "case \"$cmd\" in\n"
                                        "  store) cat > \"$store/$id\" ;;\n"
                                        "  lookup) [ -f \"$store/$id\" ] && cat \"$store/$id\" || exit 1 ;;\n"
                                        "  clear) rm -f \"$store/$id\" ;;\n"
                                        "esac\n"));
        QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        return path;
    }

    static QByteArray readAll(const QString &path)
    {
        QFile file(path);
        return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
    }

    static void write(const QString &path, const QByteArray &contents)
    {
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(contents);
    }
};

QTEST_MAIN(StreamAllTests)
#include "stream-all_tests.moc"
