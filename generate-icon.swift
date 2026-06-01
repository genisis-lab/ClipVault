#!/usr/bin/env swift
import AppKit

// Renders a 1024×1024 ClipVault app icon: a rounded-rect blue gradient tile
// with the SF Symbol "doc.on.clipboard" centered in white. Output PNG path is
// passed as the first argument.

let size = 1024.0
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no graphics context")
}

// Rounded-rect background with a vertical blue gradient.
let inset = size * 0.06
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = size * 0.22
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
path.addClip()

let colors = [NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.98, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.85, alpha: 1).cgColor]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: 0, y: 0),
                       options: [])

// Centered SF Symbol glyph in white.
let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    let r = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let gw = symbol.size.width, gh = symbol.size.height
    let origin = CGPoint(x: (size - gw) / 2, y: (size - gh) / 2)
    tinted.draw(in: CGRect(origin: origin, size: symbol.size))
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to render PNG")
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
