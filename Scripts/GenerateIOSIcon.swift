#!/usr/bin/env swift
//
// Draws Doctor's iOS app icon — the same capsule-split-on-a-diagonal mark as
// the Mac icon (Scripts/GenerateIcon.swift), adapted for iOS's edge-to-edge
// convention: no inset plate, no self-drawn rounded corners or plate-edge
// stroke (iOS applies its own corner mask), one fully opaque 1024×1024 PNG —
// modern Xcode asset catalogs need only that single size.
//
// Usage: swift Scripts/GenerateIOSIcon.swift <output.png>

import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/AppIcon-1024.png"

// MARK: - Palette (identical to the Mac icon)

private enum Palette {
    static let ink = CGColor(red: 0.063, green: 0.067, blue: 0.078, alpha: 1)   // #101114
    static let shell = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)       // #FFFFFF
    static let paperDark = CGColor(red: 0.871, green: 0.859, blue: 0.831, alpha: 1)  // #DEDBD4
    static let paperLight = CGColor(red: 0.973, green: 0.969, blue: 0.953, alpha: 1) // #F8F7F3
}

// MARK: - Geometry
//
// Same proportions as the Mac icon's capsule, applied directly to the full
// 1024pt canvas rather than to an inset plate — no padding to eat into, which
// is also why iOS icons conventionally read a touch larger than their macOS
// counterparts at the same nominal size.

private enum Metric {
    static let capsuleLength: CGFloat = 576.0 / 1024.0
    static let capsuleWidth: CGFloat = 232.0 / 1024.0
    static let hairline: CGFloat = 16.0 / 1024.0
    static let tilt = CGFloat.pi / 4
}

private func hairlineWidth(canvas: CGFloat, proportion: CGFloat, minimum: CGFloat = 1.0) -> CGFloat {
    max(canvas * proportion, minimum)
}

func drawIcon(in ctx: CGContext, size s: CGFloat) {
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // ---- Paper, full bleed -------------------------------------------------
    let canvas = CGRect(x: 0, y: 0, width: s, height: s)
    ctx.saveGState()
    ctx.addRect(canvas)
    ctx.clip()
    if let space = CGColorSpace(name: CGColorSpace.sRGB),
       let gradient = CGGradient(
        colorsSpace: space,
        colors: [Palette.paperDark, Palette.paperLight] as CFArray,
        locations: [0, 1]
       ) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: canvas.maxX, y: canvas.maxY),
            end: CGPoint(x: canvas.minX, y: canvas.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // ---- Capsule -------------------------------------------------------
    let length = s * Metric.capsuleLength
    let width = s * Metric.capsuleWidth
    let capsule = CGRect(x: -length / 2, y: -width / 2, width: length, height: width)
    let capsulePath = CGPath(
        roundedRect: capsule,
        cornerWidth: width / 2,
        cornerHeight: width / 2,
        transform: nil
    )

    ctx.saveGState()
    ctx.translateBy(x: s / 2, y: s / 2)
    ctx.rotate(by: Metric.tilt)

    ctx.addPath(capsulePath)
    ctx.setFillColor(Palette.shell)
    ctx.fillPath()

    ctx.saveGState()
    ctx.addPath(capsulePath)
    ctx.clip()
    ctx.setFillColor(Palette.ink)
    ctx.fill(CGRect(x: -length / 2, y: -width, width: length / 2, height: width * 2))
    ctx.restoreGState()

    ctx.addPath(capsulePath)
    ctx.setStrokeColor(Palette.ink)
    ctx.setLineWidth(hairlineWidth(canvas: s, proportion: Metric.hairline))
    ctx.strokePath()

    ctx.restoreGState()
}

func pngData(size: Int) -> Data? {
    // No alpha channel: the App Store rejects an icon that has one, and
    // there's nothing transparent to lose — the gradient fills the canvas
    // edge to edge.
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          )
    else { return nil }

    drawIcon(in: ctx, size: CGFloat(size))

    guard let cgImage = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])
}

guard let data = pngData(size: 1024) else {
    FileHandle.standardError.write(Data("Could not render the icon\n".utf8))
    exit(1)
}

let outURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
do {
    try data.write(to: outURL)
    print("Wrote \(outURL.path)")
} catch {
    FileHandle.standardError.write(Data("Icon generation failed: \(error)\n".utf8))
    exit(1)
}
