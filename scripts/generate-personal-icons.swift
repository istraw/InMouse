#!/usr/bin/env swift
import AppKit

// Run from the repository root after replacing branding/InMouse-icon-source.png.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("branding/InMouse-icon-source.png")
guard let source = NSImage(contentsOf: sourceURL) else { fatalError("Missing icon source") }
let assets = root.appendingPathComponent("StrokeMouse/Resources/Assets.xcassets")

func render(size: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Cannot allocate icon") }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill(using: .copy)
    // Preserve the transparent silhouette, with the standard macOS Dock safe area.
    let side = CGFloat(size) * 0.82
    let inset = (CGFloat(size) - side) / 2
    source.draw(in: NSRect(x: inset, y: inset, width: side, height: side),
                from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    return data
}

let catalog = assets.appendingPathComponent("AppIcon.appiconset")
let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog.appendingPathComponent("Contents.json"))) as! [String: Any]
for entry in contents["images"] as! [[String: String]] {
    let logicalSize = Int(entry["size"]!.split(separator: "x")[0])!
    let scale = entry["scale"] == "2x" ? 2 : 1
    try render(size: logicalSize * scale).write(to: catalog.appendingPathComponent(entry["filename"]!))
}
try render(size: 1024).write(to: assets.appendingPathComponent("BrandAppIcon.imageset/BrandAppIcon.png"))
print("Generated 10 AppIcon sizes and the shared About/Dock image with transparency.")
