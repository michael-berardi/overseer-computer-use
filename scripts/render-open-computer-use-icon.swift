#!/usr/bin/env swift

import AppKit
import Foundation

enum IconRenderError: Error {
    case invalidArguments
    case contextUnavailable(Int)
    case pngEncodingFailed(String)
}

let outputDirectoryURL = try {
    let arguments = CommandLine.arguments.dropFirst()
    guard arguments.count == 1 else {
        throw IconRenderError.invalidArguments
    }

    return URL(fileURLWithPath: String(arguments[arguments.startIndex]), isDirectory: true)
}()

try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true, attributes: nil)

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (fileName, pixelSize) in iconFiles {
    try writeIconPNG(named: fileName, pixelSize: pixelSize, to: outputDirectoryURL)
}

func writeIconPNG(named fileName: String, pixelSize: Int, to directoryURL: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw IconRenderError.contextUnavailable(pixelSize)
    }

    bitmap.size = NSSize(width: CGFloat(pixelSize), height: CGFloat(pixelSize))

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconRenderError.contextUnavailable(pixelSize)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)).fill()
    drawAppIcon(size: CGFloat(pixelSize))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw IconRenderError.pngEncodingFailed(fileName)
    }

    try pngData.write(to: directoryURL.appendingPathComponent(fileName))
}

func drawAppIcon(size: CGFloat) {
    // Original Overseer geometric mark: no gradients, glows, or third-party artwork.
    let inset = size * 0.09
    let tileRect = CGRect(origin: .zero, size: CGSize(width: size, height: size)).insetBy(dx: inset, dy: inset)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: size * 0.20, yRadius: size * 0.20)
    NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
    tile.fill()
    NSColor(calibratedWhite: 0.23, alpha: 1).setStroke()
    tile.lineWidth = max(1, size * 0.012)
    tile.stroke()

    let center = CGPoint(x: size / 2, y: size / 2)
    let radius = size * 0.285
    let ring = NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    ring.lineWidth = max(1.5, size * 0.045)
    NSColor(calibratedRed: 0.70, green: 0.56, blue: 1, alpha: 1).setStroke()
    ring.stroke()

    let diamondRadius = size * 0.13
    let diamond = NSBezierPath()
    diamond.move(to: CGPoint(x: center.x, y: center.y + diamondRadius))
    diamond.line(to: CGPoint(x: center.x + diamondRadius, y: center.y))
    diamond.line(to: CGPoint(x: center.x, y: center.y - diamondRadius))
    diamond.line(to: CGPoint(x: center.x - diamondRadius, y: center.y))
    diamond.close()
    NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
    diamond.fill()
}
