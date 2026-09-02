import AppKit
import ImageIO
import UniformTypeIdentifiers

// Кладёт PNG с прозрачностью на непрозрачный фон 1024x1024 и сохраняет без альфа-канала.
// SVG сначала отрисовывается в PNG:  qlmanage -t -s 1024 -o out_dir app-icon.svg
// Использование: render-icon input.png output.png [bgHex] [scale]
let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let bgHex = args.count > 3 ? args[3] : "FFFFFF"
let scale = args.count > 4 ? Double(args[4]) ?? 1.0 : 1.0

func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
    var v: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&v)
    return (CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
}

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("cannot read \(input.path)\n".utf8)); exit(1)
}
let size = 1024
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    FileHandle.standardError.write(Data("cannot create context\n".utf8)); exit(1)
}
let (r, g, b) = rgb(bgHex)
ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
let side = Double(size) * scale
let origin = (Double(size) - side) / 2
ctx.interpolationQuality = .high
ctx.draw(image, in: CGRect(x: origin, y: origin, width: side, height: side))
guard let result = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("cannot write\n".utf8)); exit(1)
}
CGImageDestinationAddImage(dest, result, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("wrote \(output.path)")
