#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#include <QCursor>
#include <QImage>
#include <QPixmap>

// macOS stores a custom pointer fill selected in Accessibility > Display >
// Pointer as an archived NSColor in the universal-access preferences domain.
// When no custom value exists, the native macOS pointer is predominantly dark.
bool macSystemPointerIsDark()
{
    CFPropertyListRef preference = CFPreferencesCopyAppValue(
        CFSTR("mousePointerFillColor"), CFSTR("com.apple.universalaccess"));
    if (!preference)
        return true;

    NSColor *color = nil;
    if (CFGetTypeID(preference) == CFDataGetTypeID()) {
        @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            id decoded = [NSKeyedUnarchiver
                unarchiveObjectWithData:(NSData *)preference];
#pragma clang diagnostic pop
            if ([decoded isKindOfClass:[NSColor class]])
                color = (NSColor *)decoded;
        } @catch (NSException *) {
            color = nil;
        }
    }

    bool dark = true;
    if (color) {
        NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        if (rgb) {
            const CGFloat luminance = 0.2126 * rgb.redComponent
                                    + 0.7152 * rgb.greenComponent
                                    + 0.0722 * rgb.blueComponent;
            dark = luminance < 0.5;
        }
    }

    CFRelease(preference);
    return dark;
}

QCursor invertedSystemArrowCursor()
{
    NSCursor *cursor = [NSCursor arrowCursor];
    NSImage *nativeImage = cursor.image;
    NSData *tiff = [nativeImage TIFFRepresentation];
    QImage image;
    if (tiff)
        image.loadFromData(static_cast<const uchar *>(tiff.bytes), int(tiff.length), "TIFF");
    if (image.isNull())
        return QCursor(Qt::ArrowCursor);

    image = image.convertToFormat(QImage::Format_ARGB32);
    for (int y = 0; y < image.height(); ++y) {
        QRgb *line = reinterpret_cast<QRgb *>(image.scanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            const int alpha = qAlpha(line[x]);
            if (alpha)
                line[x] = qRgba(255-qRed(line[x]), 255-qGreen(line[x]),
                                255-qBlue(line[x]), alpha);
        }
    }
    const qreal scale = nativeImage.size.width > 0
        ? image.width() / nativeImage.size.width : 1.0;
    QPixmap pixmap = QPixmap::fromImage(image);
    pixmap.setDevicePixelRatio(scale);
    const NSPoint hotSpot = cursor.hotSpot;
    return QCursor(pixmap, int(hotSpot.x), int(hotSpot.y));
}
