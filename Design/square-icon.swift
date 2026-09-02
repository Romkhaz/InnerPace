import AppKit
import ImageIO
import UniformTypeIdentifiers

// Берёт картинку иконки со скруглённым квадратом на белом поле, находит границы
// тёмного квадрата, вырезает его и кладёт в квадрат 1024x1024 на чёрном фоне:
// белые уголки исходника закрываются, App Store сам скругляет углы.
// Использование: square-icon input.png output.png
let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("cannot read \(input.path)\n".utf8)); exit(1)
}

// Растр в RGBA, чтобы найти границы тёмной области.
let w = image.width, h = image.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let lum = (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
        if lum < 90 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
guard maxX > minX, maxY > minY else { FileHandle.standardError.write(Data("no dark area\n".utf8)); exit(1) }
// Контекст CoreGraphics считает y снизу, пересчитываем в координаты картинки.
let crop = CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
guard let cropped = image.cropping(to: crop) else { exit(1) }
print("crop \(crop)")

let size = 1024
guard let out = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
out.setFillColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
out.fill(CGRect(x: 0, y: 0, width: size, height: size))
// Обрезаем по скруглённому квадрату исходника, чтобы его белые уголки не попали в кадр.
// Картинку рисуем чуть крупнее квадрата, чтобы светлая кромка исходника ушла за край.
let overscan = Double(size) * 0.035
let radius = Double(size) * 0.19
let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                  cornerWidth: radius, cornerHeight: radius, transform: nil)
out.saveGState()
out.addPath(path)
out.clip()
out.interpolationQuality = .high
out.draw(cropped, in: CGRect(x: -overscan, y: -overscan,
                             width: Double(size) + overscan * 2, height: Double(size) + overscan * 2))
out.restoreGState()

guard let result = out.makeImage(),
      let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, result, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("wrote \(output.path)")
