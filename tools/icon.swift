import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.09, green: 0.28, blue: 0.22, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor(calibratedRed: 0.83, green: 0.94, blue: 0.85, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 246, y: 214, width: 532, height: 596), xRadius: 55, yRadius: 55).fill()
NSColor(calibratedRed: 0.17, green: 0.47, blue: 0.35, alpha: 1).setFill()
for y in [620, 510, 400] {
    NSBezierPath(roundedRect: NSRect(x: 346, y: y, width: 332, height: 24), xRadius: 12, yRadius: 12).fill()
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
