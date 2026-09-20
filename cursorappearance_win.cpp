#include <QCursor>
#include <QImage>
#include <QPixmap>
#include <algorithm>
#include <windows.h>

static QImage renderCursor(HCURSOR cursor, int width, int height, QRgb background)
{
    QImage image(width, height, QImage::Format_ARGB32);
    image.fill(background);
    HDC dc = CreateCompatibleDC(nullptr);
    BITMAPINFO info = {};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void *bits = nullptr;
    HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
    HGDIOBJ old = SelectObject(dc, bitmap);
    const COLORREF bg = RGB(qRed(background), qGreen(background), qBlue(background));
    HBRUSH brush = CreateSolidBrush(bg);
    RECT rect{0, 0, width, height};
    FillRect(dc, &rect, brush);
    DrawIconEx(dc, 0, 0, cursor, width, height, 0, nullptr, DI_NORMAL);
    memcpy(image.bits(), bits, image.sizeInBytes());
    SelectObject(dc, old);
    DeleteObject(brush);
    DeleteObject(bitmap);
    DeleteDC(dc);
    return image;
}

QCursor invertedSystemArrowCursor()
{
    HCURSOR cursor = LoadCursorW(nullptr, IDC_ARROW);
    ICONINFO iconInfo = {};
    GetIconInfo(cursor, &iconInfo);
    const int width = GetSystemMetrics(SM_CXCURSOR);
    const int height = GetSystemMetrics(SM_CYCURSOR);
    QImage onBlack = renderCursor(cursor, width, height, qRgb(0, 0, 0));
    QImage onWhite = renderCursor(cursor, width, height, qRgb(255, 255, 255));
    QImage result(width, height, QImage::Format_ARGB32);
    result.fill(Qt::transparent);

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const QColor b = onBlack.pixelColor(x, y);
            const QColor w = onWhite.pixelColor(x, y);
            const int backgroundPart = ((w.red()-b.red()) + (w.green()-b.green()) + (w.blue()-b.blue())) / 3;
            const int alpha = std::clamp(255-backgroundPart, 0, 255);
            if (alpha < 4) continue;
            const int r = std::clamp(b.red()*255/alpha, 0, 255);
            const int g = std::clamp(b.green()*255/alpha, 0, 255);
            const int bl = std::clamp(b.blue()*255/alpha, 0, 255);
            result.setPixelColor(x, y, QColor(255-r, 255-g, 255-bl, alpha));
        }
    }
    if (iconInfo.hbmColor) DeleteObject(iconInfo.hbmColor);
    if (iconInfo.hbmMask) DeleteObject(iconInfo.hbmMask);
    return QCursor(QPixmap::fromImage(result), iconInfo.xHotspot, iconInfo.yHotspot);
}
