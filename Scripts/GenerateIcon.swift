#!/usr/bin/env swift
//
// Draws Doctor's app icon with Core Graphics and packs it into an .icns.
//
// The mark is a capsule split black and white on a diagonal: Doctor is
// medicine, and the two halves are the two views — Source and Preview, one
// document seen two ways.
//
// Keeping the icon as code means there is no binary blob in the repo, no design
// tool in the build, and — the part that actually matters — each rendition is
// *drawn* at its own size rather than scaled down from one master. A 16pt icon
// is not a small 1024pt icon; see `hairlineWidth` below.
//
// Usage: swift Scripts/GenerateIcon.swift <output.icns>

import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/AppIcon.icns"

// MARK: - Palette

private enum Palette {
    /// The ink half, and the hairline around the whole capsule.
    static let ink = CGColor(red: 0.063, green: 0.067, blue: 0.078, alpha: 1)   // #101114
    static let shell = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)       // #FFFFFF

    /// Paper, running dark at the top right to light at the bottom left —
    /// opposite to the capsule, so the white half sits against the darker end
    /// of the plate and the ink half against the lighter one. Each half gets
    /// the local contrast it needs, which is what keeps the split legible once
    /// the hairline is too thin to help.
    static let paperDark = CGColor(red: 0.871, green: 0.859, blue: 0.831, alpha: 1)  // #DEDBD4
    static let paperLight = CGColor(red: 0.973, green: 0.969, blue: 0.953, alpha: 1) // #F8F7F3

    /// A faint inner edge so a pale plate still has a boundary on a light dock.
    static let plateEdge = CGColor(red: 0.086, green: 0.094, blue: 0.110, alpha: 0.13)
}

// MARK: - Geometry
//
// All proportions are of the 1024pt canvas, so the drawing is resolution
// independent and the numbers stay readable against Apple's icon grid.

private enum Metric {
    /// Apple's icon grid: artwork occupies 824 of 1024 points, centred.
    static let plateInset: CGFloat = 100.0 / 1024.0
    /// The macOS squircle proportion.
    static let plateRadius: CGFloat = 0.2237
    /// A 2.48 : 1 shell, close to a real size-0 capsule.
    static let capsuleLength: CGFloat = 576.0 / 1024.0
    static let capsuleWidth: CGFloat = 232.0 / 1024.0
    static let hairline: CGFloat = 16.0 / 1024.0
    static let plateEdge: CGFloat = 6.0 / 1024.0
    /// Tilt, with the seam perpendicular to the long axis — which is where the
    /// seam is on an actual capsule, so it reads as a pill rather than a shape
    /// with a line through it.
    static let tilt = CGFloat.pi / 4
}

/// Strokes are the first thing to vanish when an icon shrinks: at 16pt a
/// proportional 16-unit hairline lands on a quarter of a pixel and disappears,
/// taking the white half's definition with it. Holding it to a device pixel
/// costs nothing at large sizes and saves the small ones.
private func hairlineWidth(canvas: CGFloat, proportion: CGFloat, minimum: CGFloat = 1.0) -> CGFloat {
    max(canvas * proportion, minimum)
}

// MARK: - Drawing

func drawIcon(in ctx: CGContext, size s: CGFloat) {
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    let inset = s * Metric.plateInset
    let plate = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = plate.width * Metric.plateRadius
    let platePath = CGPath(
        roundedRect: plate,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )

    // ---- Paper -----------------------------------------------------------
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    if let space = CGColorSpace(name: CGColorSpace.sRGB),
       let gradient = CGGradient(
        colorsSpace: space,
        colors: [Palette.paperDark, Palette.paperLight] as CFArray,
        locations: [0, 1]
       ) {
        // Bitmap contexts are y-up, so maxY is the top of the plate.
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: plate.maxX, y: plate.maxY),
            end: CGPoint(x: plate.minX, y: plate.minY),
            options: []
        )
    }

    // Stroke at double width inside the clip, so the edge stays within the
    // plate silhouette instead of haloing outside it.
    ctx.addPath(platePath)
    ctx.setStrokeColor(Palette.plateEdge)
    ctx.setLineWidth(hairlineWidth(canvas: s, proportion: Metric.plateEdge, minimum: 0.75) * 2)
    ctx.strokePath()
    ctx.restoreGState()

    // ---- Capsule ---------------------------------------------------------
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
    // Positive rotation is counter-clockwise here, so the capsule points up
    // and to the right and local -x becomes the lower-left half.
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

    drawIcon(in: ctx, size: CGFloat(size))

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
