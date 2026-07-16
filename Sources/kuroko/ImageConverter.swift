import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ConvertError: Error, CustomStringConvertible {
    case unreadable
    case undecodable
    case encodeFailed

    var description: String {
        switch self {
        case .unreadable: return "could not open file as an image"
        case .undecodable: return "image has no decodable frames"
        case .encodeFailed: return "failed to encode output"
        }
    }
}

struct ConversionOutcome {
    let output: URL
    let kind: String // "jpeg", "png", "gif"
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case auto, jpeg, png, gif

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .gif: return "GIF"
        }
    }
}

struct ConversionOptions {
    var format: OutputFormat = .auto
    var jpegQuality: Double
    var animatedToGIF: Bool = true
    /// nil = write next to the original
    var destinationDir: URL? = nil
}

enum ImageConverter {

    /// Watcher/CLI entry point: auto format rules, output next to the original.
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

        let type: UTType = resolved == .png ? .png : .jpeg
        let ext = resolved == .png ? "png" : "jpg"
        let output = uniqueOutputURL(for: url, ext: ext, in: options.destinationDir)
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, type.identifier as CFString, 1, nil
        ) else { throw ConvertError.encodeFailed }

        var addOptions: [CFString: Any] = [:]
        if type == .jpeg {
            addOptions[kCGImageDestinationLossyCompressionQuality] = options.jpegQuality
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, addOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw ConvertError.encodeFailed
        }
        return ConversionOutcome(output: output, kind: ext == "png" ? "png" : "jpeg")
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
