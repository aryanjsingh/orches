import AppKit

enum SVGImageRenderer {
    private static var cache: [String: NSImage] = [:]

    static func image(named name: String, pointSize: CGFloat, tintable: Bool) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let cacheKey = "\(name)-\(pointSize)-\(scale)-\(tintable)"
        if let cached = cache[cacheKey] {
            return cached
        }

        guard let url = Bundle.orches.url(forResource: name, withExtension: "svg"),
              let source = NSImage(contentsOf: url) else {
            return nil
        }

        let pixelDimension = Int(ceil(pointSize * scale))
        guard let bitmap = rasterize(
            source,
            pixelDimension: pixelDimension,
            pointSize: pointSize
        ) else {
            return nil
        }

        if tintable {
            bitmap.isTemplate = true
        }

        cache[cacheKey] = bitmap
        return bitmap
    }

    private static func rasterize(
        _ source: NSImage,
        pixelDimension: Int,
        pointSize: CGFloat
    ) -> NSImage? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelDimension,
            pixelsHigh: pixelDimension,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        rep.size = NSSize(width: pointSize, height: pointSize)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context

        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: pixelDimension, height: pixelDimension).fill()

        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let fitScale = min(
            CGFloat(pixelDimension) / sourceSize.width,
            CGFloat(pixelDimension) / sourceSize.height
        )
        let drawWidth = sourceSize.width * fitScale
        let drawHeight = sourceSize.height * fitScale
        let drawRect = NSRect(
            x: (CGFloat(pixelDimension) - drawWidth) / 2,
            y: (CGFloat(pixelDimension) - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        )

        source.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [
                .interpolation: NSImageInterpolation.high,
            ]
        )

        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.addRepresentation(rep)
        return image
    }
}
