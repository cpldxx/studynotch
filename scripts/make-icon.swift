// Draws the app icon and writes Resources/AppIcon.icns plus a PNG for the website.
// Run from the project folder:  swift scripts/make-icon.swift
import AppKit

let ink = CGColor(red: 0.078, green: 0.137, blue: 0.231, alpha: 1)        // #14233B
let highlighter = CGColor(red: 1.0, green: 0.914, blue: 0.29, alpha: 1)   // #FFE94A
let paper = CGColor(red: 1, green: 1, blue: 1, alpha: 0.9)
let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

func pill(_ ctx: CGContext, _ rect: CGRect, _ radius: CGFloat, _ color: CGColor) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
}

/// A page under a notch, with the middle line highlighted. Drawn on a 1024 grid.
func draw(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.addPath(shape)
    ctx.setFillColor(ink)
    ctx.fillPath()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    // The notch hangs from the top edge.
    pill(ctx, CGRect(x: 352, y: 826, width: 320, height: 160), 46, black)
    // Three lines of text; the highlighter runs across the middle one.
    pill(ctx, CGRect(x: 250, y: 640, width: 524, height: 46), 23, paper)
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 500)
    ctx.rotate(by: -0.035)
    pill(ctx, CGRect(x: -302, y: -62, width: 604, height: 124), 30, highlighter)
    ctx.restoreGState()
    pill(ctx, CGRect(x: 250, y: 477, width: 430, height: 46), 23, ink)
    pill(ctx, CGRect(x: 250, y: 314, width: 350, height: 46), 23, paper)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL) {
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset", isDirectory: true)
try? fm.removeItem(at: iconset)
try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        write(draw(pixels: points * scale), to: iconset.appendingPathComponent(name))
    }
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try? tool.run()
tool.waitUntilExit()

let siteAssets = root.appendingPathComponent("site/assets/img", isDirectory: true)
try? fm.createDirectory(at: siteAssets, withIntermediateDirectories: true)
write(draw(pixels: 512), to: siteAssets.appendingPathComponent("app-icon.png"))
write(draw(pixels: 180), to: siteAssets.appendingPathComponent("apple-touch-icon.png"))

print(tool.terminationStatus == 0 ? "wrote \(icns.lastPathComponent) and site icons" : "iconutil failed")
