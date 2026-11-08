// 生成 Nopeject.app 图标：
// 使用与菜单栏托盘完全相同的 SF Symbol（externaldrive.badge.checkmark），
// 由 macOS AppKit 自行渲染字形（无任何手绘位图素材），合成到系统风格圆角渐变底板上，
// 输出标准 iconset 并用 iconutil 打包为 .icns。
//
// 用法：swift scripts/gen-icon.swift <输出 .icns 路径>

import AppKit

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : ".build/AppIcon.icns"

let symbolName = "externaldrive.badge.checkmark"
let canvas: CGFloat = 1024

// MARK: - 合成 1024px 主图

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// 底板：macOS 应用图标风格圆角矩形 + 纵向系统蓝渐变
let inset: CGFloat = 100
let plate = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 228, yRadius: 228)
NSGradient(colors: [
    NSColor(calibratedRed: 0.38, green: 0.58, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.92, alpha: 1),
])?.draw(in: platePath, angle: -90)

// 字形：托盘同款符号，白色渲染
let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
let configured = base.withSymbolConfiguration(
    NSImage.SymbolConfiguration(pointSize: 300, weight: .medium)
)!
let tinted = NSImage(size: configured.size)
tinted.lockFocus()
configured.draw(
    in: NSRect(origin: .zero, size: configured.size),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)
NSColor.white.setFill()
NSRect(origin: .zero, size: configured.size).fill(using: .sourceAtop)
tinted.unlockFocus()

tinted.draw(in: NSRect(
    x: (canvas - configured.size.width) / 2,
    y: (canvas - configured.size.height) / 2,
    width: configured.size.width,
    height: configured.size.height
))
image.unlockFocus()

// MARK: - 输出 iconset 各尺寸

func pngData(_ source: NSImage, side: CGFloat) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(side), pixelsHigh: Int(side),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
let tempDir = fm.temporaryDirectory
    .appendingPathComponent("nopeject-iconset-\(UUID().uuidString)")
let iconset = tempDir.appendingPathComponent("AppIcon.iconset")
try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, side) in variants {
    guard let data = pngData(image, side: side) else {
        FileHandle.standardError.write(Data("gen-icon: 渲染 \(name) 失败\n".utf8))
        exit(1)
    }
    try? data.write(to: iconset.appendingPathComponent(name))
}

// iconutil 打包
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", outPath]
try? task.run()
task.waitUntilExit()

try? fm.removeItem(at: tempDir)

if task.terminationStatus != 0 || !fm.fileExists(atPath: outPath) {
    FileHandle.standardError.write(Data("gen-icon: iconutil 失败\n".utf8))
    exit(1)
}
print("gen-icon: 已生成 \(outPath)")
