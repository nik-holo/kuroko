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

enum ImageConverter {

    /// Converts a WebP/AVIF/HEIC file next to the original.
    /// Static images become JPEG, or PNG when they carry an alpha channel.
    /// Animated images become GIF when `animatedToGIF` is on (otherwise first frame is used).
    static func convert(_ url: URL, jpegQuality: Double, animatedToGIF: Bool) throws -> ConversionOutcome {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ConvertError.unreadable
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw ConvertError.undecodable }

        if frameCount > 1 && animatedToGIF {
            return try encodeGIF(source, frameCount: frameCount, original: url)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let hasAlpha = (properties?[kCGImagePropertyHasAlpha] as? Bool) ?? false

        let type: UTType = hasAlpha ? .png : .jpeg
        let output = uniqueOutputURL(for: url, ext: hasAlpha ? "png" : "jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, type.identifier as CFString, 1, nil
        ) else { throw ConvertError.encodeFailed }

        var options: [CFString: Any] = [:]
        if type == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw ConvertError.encodeFailed
        }
        return ConversionOutcome(output: output, kind: hasAlpha ? "png" : "jpeg")
    }

    private static func encodeGIF(_ source: CGImageSource, frameCount: Int, original: URL) throws -> ConversionOutcome {
        let output = uniqueOutputURL(for: original, ext: "gif")
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
    private static func uniqueOutputURL(for original: URL, ext: String) -> URL {
        let directory = original.deletingLastPathComponent()
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
