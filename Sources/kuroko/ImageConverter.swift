import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ConvertError: Error, CustomStringConvertible {
    case unreadable
    case undecodable
    case unsupportedOutput
    case encodeFailed

    var description: String {
        switch self {
        case .unreadable: return "could not open file as an image"
        case .undecodable: return "image has no decodable frames"
        case .unsupportedOutput: return "this macOS version cannot encode the chosen format"
        case .encodeFailed: return "failed to encode output"
        }
    }
}

struct ConversionOutcome {
    let output: URL
    let kind: String
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case auto, jpeg, png, gif, webp, avif, heic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .gif: return "GIF"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .heic: return "HEIC"
        }
    }

    var utType: UTType? {
        switch self {
        case .auto: return nil
        case .jpeg: return .jpeg
        case .png: return .png
        case .gif: return .gif
        case .webp: return .webP
        case .avif: return UTType("public.avif")
        case .heic: return .heic
        }
    }

    var fileExtension: String {
        switch self {
        case .auto: return ""
        case .jpeg: return "jpg"
        case .png: return "png"
        case .gif: return "gif"
        case .webp: return "webp"
        case .avif: return "avif"
        case .heic: return "heic"
        }
    }

    var isLossy: Bool {
        switch self {
        case .jpeg, .webp, .avif, .heic: return true
        case .auto: return true  // auto may resolve to JPEG, so quality applies
        case .png, .gif: return false
        }
    }

    /// Formats this macOS version can actually encode (ImageIO support varies).
    static let encodable: [OutputFormat] = {
        let supported = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return allCases.filter { format in
            guard let ut = format.utType else { return true }  // .auto
            return supported.contains(ut.identifier)
        }
    }()
}

struct ConversionOptions {
    var format: OutputFormat = .auto
    var jpegQuality: Double
    var animatedToGIF: Bool = true
    /// nil = write next to the original
    var destinationDir: URL? = nil
    /// nil = keep original pixel size; otherwise downscale so the longest side fits
    var maxDimension: Int? = nil
    /// nil = no limit; otherwise best-effort cap on output file size in bytes:
    /// quality is lowered first (lossy formats), then dimensions are reduced
    var maxFileBytes: Int? = nil
    /// re-encode pixels only, dropping EXIF/GPS/etc. (orientation is baked in)
    var stripMetadata: Bool = false
}

enum ImageConverter {

    /// Watcher entry point: auto format rules, output next to the original.
    static func convert(_ url: URL, jpegQuality: Double, animatedToGIF: Bool) throws -> ConversionOutcome {
        try convert(url, options: ConversionOptions(jpegQuality: jpegQuality, animatedToGIF: animatedToGIF))
    }

    /// Converts any ImageIO-decodable image.
    /// Auto rules: animated → GIF (when enabled), alpha → PNG, otherwise JPEG.
    /// An explicit format forces the output; animated sources collapse to the
    /// first frame unless the target is GIF.
    static func convert(_ url: URL, options: ConversionOptions) throws -> ConversionOutcome {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ConvertError.unreadable
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw ConvertError.undecodable }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let hasAlpha = (properties?[kCGImagePropertyHasAlpha] as? Bool) ?? false
        let animated = frameCount > 1

        let resolved: OutputFormat
        switch options.format {
        case .auto:
            resolved = (animated && options.animatedToGIF) ? .gif : (hasAlpha ? .png : .jpeg)
        default:
            resolved = options.format
        }

        if resolved == .gif {
            return try encodeGIF(source, frameCount: frameCount, original: url,
                                 destinationDir: options.destinationDir)
        }

        guard let type = resolved.utType, OutputFormat.encodable.contains(resolved) else {
            throw ConvertError.unsupportedOutput
        }

        let width = (properties?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let originalMax = max(width, height, 1)

        // One encode attempt, in memory so size-capped conversions can iterate.
        func attempt(quality: Double, maxPixel: Int?) throws -> Data {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data, type.identifier as CFString, 1, nil
            ) else { throw ConvertError.encodeFailed }
            var addOptions: [CFString: Any] = [:]
            if resolved.isLossy {
                addOptions[kCGImageDestinationLossyCompressionQuality] = quality
            }
            if options.stripMetadata || maxPixel != nil {
                // Thumbnail decode: applies EXIF orientation to the pixels
                // (so no metadata is needed) and handles downscaling.
                let thumbOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel ?? originalMax,
                    kCGImageSourceShouldCacheImmediately: true,
                ]
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
                    throw ConvertError.undecodable
                }
                CGImageDestinationAddImage(destination, image, addOptions as CFDictionary)
            } else {
                // straight re-encode, metadata (EXIF orientation etc.) preserved
                CGImageDestinationAddImageFromSource(destination, source, 0, addOptions as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { throw ConvertError.encodeFailed }
            return data as Data
        }

        var quality = options.jpegQuality
        var maxPixel = options.maxDimension
        var encoded = try attempt(quality: quality, maxPixel: maxPixel)

        if let cap = options.maxFileBytes, encoded.count > cap {
            // best effort: walk quality down first (lossy formats only)...
            if resolved.isLossy {
                while encoded.count > cap, quality > 0.35 {
                    quality = max(0.3, quality * 0.65)
                    encoded = try attempt(quality: quality, maxPixel: maxPixel)
                }
            }
            // ...then shrink dimensions until it fits (or gets unreasonably small)
            var pixel = maxPixel ?? originalMax
            while encoded.count > cap, pixel > 256 {
                pixel = Int(Double(pixel) * 0.75)
                maxPixel = pixel
                encoded = try attempt(quality: quality, maxPixel: pixel)
            }
        }

        let output = uniqueOutputURL(for: url, ext: resolved.fileExtension, in: options.destinationDir)
        do {
            try encoded.write(to: output)
        } catch {
            throw ConvertError.encodeFailed
        }
        return ConversionOutcome(output: output, kind: resolved.fileExtension)
    }

    private static func encodeGIF(_ source: CGImageSource, frameCount: Int, original: URL,
                                  destinationDir: URL? = nil) throws -> ConversionOutcome {
        let output = uniqueOutputURL(for: original, ext: "gif", in: destinationDir)
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.gif.identifier as CFString, frameCount, nil
        ) else { throw ConvertError.encodeFailed }

        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        var added = 0
        for index in 0..<frameCount {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frameDelay(source, at: index)
                ]
            ]
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
            added += 1
        }
        guard added > 0, CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw ConvertError.encodeFailed
        }
        return ConversionOutcome(output: output, kind: "gif")
    }

    private static func frameDelay(_ source: CGImageSource, at index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }
        for containerKey in [kCGImagePropertyWebPDictionary, kCGImagePropertyGIFDictionary, kCGImagePropertyHEICSDictionary] {
            guard let container = properties[containerKey] as? [CFString: Any] else { continue }
            for delayKey in [kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime] {
                if let delay = container[delayKey] as? Double, delay > 0 {
                    return delay
                }
            }
        }
        return 0.1
    }

    /// photo.webp -> photo.jpg; if taken, photo 2.jpg, photo 3.jpg, ...
    private static func uniqueOutputURL(for original: URL, ext: String, in destinationDir: URL? = nil) -> URL {
        let directory = destinationDir ?? original.deletingLastPathComponent()
        let base = original.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }
}
