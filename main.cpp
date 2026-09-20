#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QCursor>
#include <QSettings>

#if defined(Q_OS_WIN) || defined(Q_OS_MACOS)
QCursor invertedSystemArrowCursor();
#endif
#ifdef Q_OS_MACOS
bool macSystemPointerIsDark();
#endif

class CursorController : public QObject
{
    Q_OBJECT
public:
    explicit CursorController(QObject *parent = nullptr) : QObject(parent) {}

    Q_INVOKABLE void enterArtboard()
    {
        if (m_active)
            return;

#if defined(Q_OS_WIN) || defined(Q_OS_MACOS)
        QGuiApplication::setOverrideCursor(invertedSystemArrowCursor());
#else
        QGuiApplication::setOverrideCursor(QCursor(Qt::ArrowCursor));
#endif
        m_active = true;
    }

    Q_INVOKABLE void leaveArtboard()
    {
        if (!m_active)
            return;
        QGuiApplication::restoreOverrideCursor();
        m_active = false;
    }

private:
    bool isSystemPointerDark() const
    {
#ifdef Q_OS_WIN
        QSettings cursors(QStringLiteral("HKEY_CURRENT_USER\\Control Panel\\Cursors"),
                          QSettings::NativeFormat);
        const QString arrow = cursors.value(QStringLiteral("Arrow")).toString().toLower();
        const QString scheme = cursors.value(QStringLiteral(".")).toString().toLower();
        // Windows' black accessibility schemes include "black" in the cursor file
        // or scheme name. The regular aero pointer is predominantly white.
        return arrow.contains(QStringLiteral("black")) ||
               scheme.contains(QStringLiteral("black")) ||
               scheme.contains(QStringLiteral("黑色"));
#elif defined(Q_OS_MACOS)
        return macSystemPointerIsDark();
#else
        return true;
#endif
    }

    bool m_active = false;
};

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    QQmlApplicationEngine engine;
    CursorController cursorController;
    engine.rootContext()->setContextProperty(QStringLiteral("cursorController"),
                                             &cursorController);
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.loadFromModule("copy_sketch", "Main");

    return QGuiApplication::exec();
}

#include "main.moc"
