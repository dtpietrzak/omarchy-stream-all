// stream-all — takes one stream from OBS and sends it to every destination you add.

#include <QGuiApplication>
#include <QSocketNotifier>
#include <csignal>
#include <sys/socket.h>
#include <unistd.h>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>

#include "backend.h"
#include "theme.h"
#include "translator.h"

// SIGTERM, SIGINT, and SIGHUP end the app through the event loop, so the
// outputs disconnect cleanly instead of being cut off. The handler only writes
// a byte; a socket notifier does the real work back in the event loop.
static int signalPipe[2];

static void onSignal(int) {
    const char byte = 1;
    if (write(signalPipe[0], &byte, 1) < 0) {}
}

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("stream-all");
    app.setApplicationVersion("0.1.0");

    // Matches the window to stream-all.desktop, so the compositor (Wayland
    // app_id) and the launcher pick up the installed icon.
    app.setDesktopFileName("stream-all");
    app.setWindowIcon(QIcon::fromTheme("stream-all"));

    QQuickStyle::setStyle("Material");

    if (socketpair(AF_UNIX, SOCK_STREAM, 0, signalPipe) == 0) {
        auto *notifier = new QSocketNotifier(signalPipe[1], QSocketNotifier::Read, &app);
        // exit(), not quit(): quit() would close the window first, and the
        // window refuses to close while live. A signal is not a user clicking
        // X, so there is nobody to ask. The byte is read so the notifier stops.
        QObject::connect(notifier, &QSocketNotifier::activated, &app, [] {
            char byte;
            if (read(signalPipe[1], &byte, 1) < 0) {}
            QCoreApplication::exit(0);
        });
        for (int sig : {SIGTERM, SIGINT, SIGHUP})
            std::signal(sig, onSignal);
    }

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    Theme theme;
    // The local server waits for the play button, so opening the app never
    // takes port 1935 or accepts a stream by surprise.
    Backend backend;

    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}
