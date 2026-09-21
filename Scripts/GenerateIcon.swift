#!/usr/bin/env swift
//
// Draws Doctor's app icon with Core Graphics and packs it into an .icns.
// Keeping the icon as code means there is no binary blob in the repo and no
// design-tool dependency in the build.
//
// Usage: swift Scripts/GenerateIcon.swift <output.icns>

import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/AppIcon.icns"

// MARK: - Drawing

func drawIcon(in ctx: CGContext, size s: CGFloat) {
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // macOS icons sit inside a margin rather than filling the canvas.
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.2237

    let plate = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Body: a deep indigo-to-teal gradient, the same family as the editor accent.
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    let colors = [
        CGColor(red: 0.26, green: 0.30, blue: 0.62, alpha: 1.0),
        CGColor(red: 0.16, green: 0.49, blue: 0.60, alpha: 1.0)
    ] as CFArray
    if let space = CGColorSpace(name: CGColorSpace.sRGB),
       let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // A soft top highlight so the plate reads as a physical object.
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.fill(CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2))
    ctx.restoreGState()

    // The mark: a stylised "M" with a descending arrow — the Markdown glyph,
    // drawn as strokes rather than text so it scales cleanly to 16pt.
    let markWidth = rect.width * 0.60
    let markHeight = markWidth * 0.52
    let markRect = CGRect(
        x: rect.midX - markWidth / 2,
        y: rect.midY - markHeight / 2,
        width: markWidth,
        height: markHeight
    )
    let stroke = max(1, markRect.height * 0.165)

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.97))
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // "M" occupies the left 58%.
    let mLeft = markRect.minX + stroke / 2
    let mRight = markRect.minX + markRect.width * 0.52
    let mBottom = markRect.minY + stroke / 2
    let mTop = markRect.maxY - stroke / 2
    let mMid = (mLeft + mRight) / 2

    ctx.beginPath()
    ctx.move(to: CGPoint(x: mLeft, y: mBottom))
    ctx.addLine(to: CGPoint(x: mLeft, y: mTop))
    ctx.addLine(to: CGPoint(x: mMid, y: mBottom + markRect.height * 0.34))
    ctx.addLine(to: CGPoint(x: mRight, y: mTop))
    ctx.addLine(to: CGPoint(x: mRight, y: mBottom))
    ctx.strokePath()

    // Descending arrow on the right.
    let aX = markRect.minX + markRect.width * 0.82
    ctx.beginPath()
    ctx.move(to: CGPoint(x: aX, y: mTop))
    ctx.addLine(to: CGPoint(x: aX, y: mBottom))
    ctx.strokePath()

    let head = markRect.width * 0.155
    ctx.beginPath()
    ctx.move(to: CGPoint(x: aX - head, y: mBottom + head))
    ctx.addLine(to: CGPoint(x: aX, y: mBottom))
    ctx.addLine(to: CGPoint(x: aX + head, y: mBottom + head))
    ctx.strokePath()
}

func pngData(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return nil }

    drawIcon(in: ctx, size: s)

    guard let cgImage = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Packaging

let fm = FileManager.default
let workDir = fm.temporaryDirectory.appendingPathComponent("doctor-icon-\(UUID().uuidString)")
let iconset = workDir.appendingPathComponent("AppIcon.iconset")

do {
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

    let variants: [(name: String, px: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024)
    ]

    for variant in variants {
        guard let data = pngData(size: variant.px) else {
            FileHandle.standardError.write(Data("Could not render \(variant.name)\n".utf8))
            exit(1)
        }
        try data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
    }

    let outURL = URL(fileURLWithPath: outputPath)
    try? fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", outURL.path]
    try process.run()
    process.waitUntilExit()

    try? fm.removeItem(at: workDir)

    if process.terminationStatus != 0 {
        FileHandle.standardError.write(Data("iconutil failed\n".utf8))
        exit(process.terminationStatus)
    }
    print("Wrote \(outURL.path)")
} catch {
    FileHandle.standardError.write(Data("Icon generation failed: \(error)\n".utf8))
    exit(1)
}
