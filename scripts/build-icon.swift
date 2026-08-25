#!/usr/bin/env swift

import AppKit
import Foundation

enum IconBuildError: LocalizedError {
    case usage
    case unreadableImage(String)
    case bitmapCreation(Int)
    case pngEncoding(Int)
    case oversizedChunk(Int)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: swift scripts/build-icon.swift <source.png> <output.icns>"
        case .unreadableImage(let path):
            "The source image could not be read: \(path)"
        case .bitmapCreation(let size):
            "Could not create the \(size) px icon bitmap."
        case .pngEncoding(let size):
            "Could not encode the \(size) px icon as PNG."
        case .oversizedChunk(let size):
            "The \(size) px icon chunk is too large for an ICNS container."
        }
    }
}

struct IconChunk {
    let type: String
    let size: Int
}

let chunks = [
    IconChunk(type: "icp4", size: 16),
    IconChunk(type: "icp5", size: 32),
    IconChunk(type: "icp6", size: 64),
    IconChunk(type: "ic07", size: 128),
    IconChunk(type: "ic08", size: 256),
    IconChunk(type: "ic09", size: 512),
    IconChunk(type: "ic10", size: 1_024)
]

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndianValue = value.bigEndian
    withUnsafeBytes(of: &bigEndianValue) { data.append(contentsOf: $0) }
}

func pngData(from image: NSImage, size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: .alphaFirst,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw IconBuildError.bitmapCreation(size)
    }

    bitmap.size = NSSize(width: size, height: size)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconBuildError.bitmapCreation(size)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    image.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconBuildError.pngEncoding(size)
    }
    return data
}

do {
    guard CommandLine.arguments.count == 3 else { throw IconBuildError.usage }
    let sourcePath = CommandLine.arguments[1]
    let outputPath = CommandLine.arguments[2]
    guard let image = NSImage(contentsOfFile: sourcePath) else {
        throw IconBuildError.unreadableImage(sourcePath)
    }

    var chunkData = Data()
    for chunk in chunks {
        let png = try pngData(from: image, size: chunk.size)
        guard png.count <= Int(UInt32.max) - 8 else {
            throw IconBuildError.oversizedChunk(chunk.size)
        }
        chunkData.append(Data(chunk.type.utf8))
        appendUInt32(UInt32(png.count + 8), to: &chunkData)
        chunkData.append(png)
    }

    guard chunkData.count <= Int(UInt32.max) - 8 else {
        throw IconBuildError.oversizedChunk(1_024)
    }
    var container = Data("icns".utf8)
    appendUInt32(UInt32(chunkData.count + 8), to: &container)
    container.append(chunkData)
    try container.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    print(outputPath)
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
