import AppKit
let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.58, green: 0.12, blue: 0.27, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 320, y: 112, width: 384, height: 800), xRadius: 115, yRadius: 115).fill()
NSColor(calibratedRed: 0.58, green: 0.12, blue: 0.27, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 386, y: 470, width: 252, height: 252)).fill()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 468, y: 552, width: 88, height: 88)).fill()
NSColor(calibratedRed: 0.58, green: 0.12, blue: 0.27, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 480, y: 778, width: 64, height: 64)).fill()
for x in [399, 555] {
    NSBezierPath(roundedRect: NSRect(x: x, y: 252, width: 70, height: 144), xRadius: 35, yRadius: 35).fill()
}
NSGraphicsContext.restoreGraphicsState()
let data = bitmap.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
