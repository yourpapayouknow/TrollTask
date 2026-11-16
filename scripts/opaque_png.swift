import Foundation
import CoreGraphics
import ImageIO

// 将 PNG 压平到不透明背景，去掉 alpha 通道。
func color(_ hex: String) -> CGColor {
    var text = hex
    if text.hasPrefix("#") { text.removeFirst() }
    var value: UInt64 = 0
    Scanner(string: text).scanHexInt64(&value)
    return CGColor(
        red: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255,
        blue: CGFloat(value & 255) / 255,
        alpha: 1
    )
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: opaque_png.swift input output [background]\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let background = args.count > 3 ? args[3] : "#F1EBE5"

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      ) else {
    FileHandle.standardError.write(Data("cannot create opaque context\n".utf8))
    exit(1)
}
context.setFillColor(color(background))
context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
guard let flattened = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("cannot create destination\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, flattened, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("cannot write png\n".utf8))
    exit(1)
}