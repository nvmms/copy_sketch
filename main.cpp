#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QCursor>
#include <QSettings>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QUrl>
#include <QVariantMap>

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

class DocumentFileController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)
public:
    explicit DocumentFileController(QObject *parent = nullptr) : QObject(parent) {}

    QString errorString() const { return m_errorString; }

    Q_INVOKABLE bool save(const QUrl &url, const QVariantMap &document)
    {
        QString path = url.toLocalFile();
        if (path.isEmpty())
            path = url.toString();
        if (QFileInfo(path).suffix().isEmpty())
            path += QStringLiteral(".linea");

        QFile file(path);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            setError(file.errorString());
            return false;
        }
        const QJsonDocument json = QJsonDocument::fromVariant(document);
        if (file.write(json.toJson(QJsonDocument::Indented)) < 0) {
            setError(file.errorString());
            return false;
        }
        setError({});
        return true;
    }

    Q_INVOKABLE QVariantMap load(const QUrl &url)
    {
        QFile file(url.toLocalFile());
        if (!file.open(QIODevice::ReadOnly)) {
            setError(file.errorString());
            return {};
        }
        QJsonParseError parseError;
        const QJsonDocument json = QJsonDocument::fromJson(file.readAll(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !json.isObject()) {
            setError(parseError.error != QJsonParseError::NoError
                         ? parseError.errorString()
                         : QStringLiteral("The file does not contain a Linea document."));
            return {};
        }
        setError({});
        return json.toVariant().toMap();
    }

signals:
    void errorStringChanged();

private:
    void setError(const QString &error)
    {
        if (m_errorString == error)
            return;
        m_errorString = error;
        emit errorStringChanged();
    }

    QString m_errorString;
};

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    QQmlApplicationEngine engine;
    CursorController cursorController;
    DocumentFileController documentFileController;
    engine.rootContext()->setContextProperty(QStringLiteral("cursorController"),
                                             &cursorController);
    engine.rootContext()->setContextProperty(QStringLiteral("documentFileController"),
                                             &documentFileController);
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
