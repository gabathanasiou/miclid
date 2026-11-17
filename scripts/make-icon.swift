#!/usr/bin/env swift
// Renders MicLid's app icon into Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift

import AppKit
import Foundation

let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = repo.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let scale = size / 1024

    // Squircle plate with a soft drop shadow.
    let inset = 100 * scale
    let plate = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let path = NSBezierPath(roundedRect: plate, xRadius: 185 * scale, yRadius: 185 * scale)

    let shadow = NSShadow()
    shadow.shadowBlurRadius = 26 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.19, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.21, green: 0.30, blue: 0.46, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.15, alpha: 1)
    ])!
    gradient.draw(in: path, angle: -90)

    // White microphone glyph.
    guard let symbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 380 * scale, weight: .semibold)) else {
        return image
    }

    let silhouette = NSImage(size: symbol.size)
    silhouette.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: symbol.size).fill()
    symbol.draw(in: NSRect(origin: .zero, size: symbol.size), from: .zero, operation: .destinationIn, fraction: 1)
    silhouette.unlockFocus()

    let glyphRect = NSRect(
        x: (size - symbol.size.width) / 2,
        y: (size - symbol.size.height) / 2 + 10 * scale,
        width: symbol.size.width,
        height: symbol.size.height
    )

    let glyphShadow = NSShadow()
    glyphShadow.shadowBlurRadius = 22 * scale
    glyphShadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
    glyphShadow.shadowColor = NSColor(white: 0, alpha: 0.25)
    NSGraphicsContext.saveGraphicsState()
    glyphShadow.set()
    silhouette.draw(in: glyphRect)
    NSGraphicsContext.restoreGraphicsState()

    // Orange status dot, matching the menu bar's pending-switch indicator.
    let dotRadius = 34 * scale
    let dotCenter = NSPoint(x: size * 0.68, y: size * 0.31)
    let dot = NSRect(
        x: dotCenter.x - dotRadius,
        y: dotCenter.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    )
    NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.12, alpha: 1).setFill()
    NSBezierPath(ovalIn: dot).fill()

    return image
}

func png(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MicLidIcon", code: 1)
    }
    try data.write(to: url)
}

let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for (name, size) in variants {
    try png(render(size: size), to: iconset.appendingPathComponent("\(name).png"))
}

let output = repo.appendingPathComponent("Resources/AppIcon.icns")
try FileManager.default.createDirectory(
    at: repo.appendingPathComponent("Resources"),
    withIntermediateDirectories: true
)

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("wrote \(output.path)")
