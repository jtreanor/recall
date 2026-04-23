#!/usr/bin/env swift
// Generates app icon and menu bar icon PNGs for Recall.
// Run from the repo root: swift scripts/generate_icons.swift

import AppKit
import CoreGraphics

// MARK: - Drawing

func drawAppIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let inset: CGFloat = size * 0.08
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

    // Background: rounded rect with indigo-to-teal gradient
    let cornerRadius = size * 0.22
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.31, green: 0.28, blue: 0.90, alpha: 1), // indigo
            CGColor(red: 0.18, green: 0.62, blue: 0.78, alpha: 1), // teal
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )
    ctx.resetClip()

    // Clipboard body
    let bodyX = size * 0.22
    let bodyY = size * 0.14
    let bodyW = size * 0.56
    let bodyH = size * 0.68
    let bodyR = size * 0.07

    let bodyPath = CGPath(
        roundedRect: CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
        cornerWidth: bodyR, cornerHeight: bodyR, transform: nil
    )
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.addPath(bodyPath)
    ctx.fillPath()

    // Clip tab at top center
    let tabW = size * 0.28
    let tabH = size * 0.10
    let tabX = (size - tabW) / 2
    let tabY = size * 0.78
    let tabR = size * 0.04

    let tabPath = CGPath(
        roundedRect: CGRect(x: tabX, y: tabY, width: tabW, height: tabH),
        cornerWidth: tabR, cornerHeight: tabR, transform: nil
    )
    ctx.setFillColor(CGColor(red: 0.31, green: 0.28, blue: 0.90, alpha: 1))
    ctx.addPath(tabPath)
    ctx.fillPath()

    // Lines on clipboard (representing text)
    ctx.setFillColor(CGColor(red: 0.60, green: 0.62, blue: 0.70, alpha: 1))
    let lineH = size * 0.05
    let lineR = lineH / 2
    let lineX = size * 0.32
    let fullLineW = size * 0.36
    let shortLineW = size * 0.24
    let lineSpacing = size * 0.115

    let lineYs: [(CGFloat, CGFloat)] = [
        (size * 0.57, fullLineW),
        (size * 0.57 - lineSpacing, fullLineW),
        (size * 0.57 - lineSpacing * 2, shortLineW),
    ]
    for (ly, lw) in lineYs {
        let lp = CGPath(roundedRect: CGRect(x: lineX, y: ly, width: lw, height: lineH),
                        cornerWidth: lineR, cornerHeight: lineR, transform: nil)
        ctx.addPath(lp)
        ctx.fillPath()
    }

    image.unlockFocus()
    return image
}

func drawMenuBarIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // Scale everything to the given size (designed at 18pt)
    let s = size / 18.0

    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))

    let lw = 1.4 * s
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Clipboard body outline
    let bodyX = 3.0 * s
    let bodyY = 2.0 * s
    let bodyW = 12.0 * s
    let bodyH = 13.0 * s
    let bodyR = 2.0 * s
    let bodyPath = CGPath(
        roundedRect: CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
        cornerWidth: bodyR, cornerHeight: bodyR, transform: nil
    )
    ctx.addPath(bodyPath)
    ctx.strokePath()

    // Clip tab
    let tabW = 5.0 * s
    let tabH = 2.5 * s
    let tabX = (size - tabW) / 2
    let tabY = size - tabH - 1.0 * s
    let tabR = 1.0 * s
    let tabPath = CGPath(
        roundedRect: CGRect(x: tabX, y: tabY, width: tabW, height: tabH),
        cornerWidth: tabR, cornerHeight: tabR, transform: nil
    )
    ctx.addPath(tabPath)
    ctx.strokePath()

    // Three lines inside
    let lineH = 1.2 * s
    let lineR = lineH / 2
    let lineX = 5.5 * s
    let lineSpacing = 2.8 * s

    let lines: [(CGFloat, CGFloat)] = [
        (4.5 * s, 7.0 * s),
        (4.5 * s + lineSpacing, 7.0 * s),
        (4.5 * s + lineSpacing * 2, 5.0 * s),
    ]
    for (ly, lw2) in lines {
        let lp = CGPath(roundedRect: CGRect(x: lineX, y: ly, width: lw2, height: lineH),
                        cornerWidth: lineR, cornerHeight: lineR, transform: nil)
        ctx.addPath(lp)
        ctx.fillPath()
    }

    image.unlockFocus()
    return image
}

// MARK: - PNG Export

func pngData(from image: NSImage, size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, to path: String) {
    let url = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
    print("  wrote \(path)")
}

// MARK: - Main

let root = "Recall/Assets.xcassets"

// App icon sizes required by macOS
let appIconSizes: [(name: String, pt: CGFloat, scale: Int)] = [
    ("16",   16,  1), ("16@2x",  16,  2),
    ("32",   32,  1), ("32@2x",  32,  2),
    ("128", 128,  1), ("128@2x", 128, 2),
    ("256", 256,  1), ("256@2x", 256, 2),
    ("512", 512,  1), ("512@2x", 512, 2),
    ("1024", 1024, 1),
]

print("Generating app icons...")
for spec in appIconSizes {
    let px = spec.pt * CGFloat(spec.scale)
    let img = drawAppIcon(size: px)
    let data = pngData(from: img, size: px)
    write(data, to: "\(root)/AppIcon.appiconset/icon_\(spec.name).png")
}

print("Generating menu bar icon...")
// 1x at 18pt = 18px, 2x = 36px
let mb1x = drawMenuBarIcon(size: 18)
let mb2x = drawMenuBarIcon(size: 36)
write(pngData(from: mb1x, size: 18), to: "\(root)/MenuBarIcon.imageset/menubar_icon.png")
write(pngData(from: mb2x, size: 36), to: "\(root)/MenuBarIcon.imageset/menubar_icon@2x.png")

print("Done.")
