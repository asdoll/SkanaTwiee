// Prints an ASCII preview of a PNG's alpha/ink so the shape can be checked
// without an image viewer.
//
//   swift /tmp/inspect_png.swift <file.png> [cols]

import Foundation
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
guard args.count > 1 else { fatalError("usage: inspect_png <file> [cols]") }
let cols = args.count > 2 ? Int(args[2])! : 56

let url = URL(fileURLWithPath: args[1])
guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    fatalError("cannot read \(args[1])")
}

let w = img.width
let h = img.height
var buf = [UInt8](repeating: 0, count: w * h * 4)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

// Alpha bbox + coverage.
var minX = w, minY = h, maxX = -1, maxY = -1
var opaque = 0
for y in 0..<h {
    for x in 0..<w {
        let a = buf[(y * w + x) * 4 + 3]
        if a > 8 {
            opaque += 1
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
}
print("\(args[1]): \(w)x\(h)  alpha>8: \(String(format: "%.1f", 100.0 * Double(opaque) / Double(w * h)))%")
print("bbox: x \(minX)...\(maxX) (\(maxX - minX + 1) px, \(String(format: "%.3f", Double(maxX - minX + 1) / Double(w)))w)"
    + "  y \(minY)...\(maxY) (\(maxY - minY + 1) px, \(String(format: "%.3f", Double(maxY - minY + 1) / Double(h)))h)")

// ASCII: the ink is the alpha; brightness shows coverage.
let rows = Int(Double(cols) * Double(h) / Double(w) / 2.0)
let cw = Double(w) / Double(cols)
let ch = Double(h) / Double(rows)
let ramp = Array(" .:-=+*#%@")
for r in 0..<rows {
    var line = ""
    for c in 0..<cols {
        var sum = 0.0
        var n = 0.0
        var y = Double(r) * ch
        while y < Double(r + 1) * ch {
            var x = Double(c) * cw
            while x < Double(c + 1) * cw {
                let px = min(Int(x), w - 1)
                let py = min(Int(y), h - 1)
                sum += Double(buf[(py * w + px) * 4 + 3]) / 255.0
                n += 1
                x += 1
            }
            y += 1
        }
        let v = n > 0 ? sum / n : 0
        // Invert: alpha 1 (ink) should be the dense character.
        let idx = Int((v * Double(ramp.count - 1)).rounded())
        line.append(ramp[idx])
    }
    print(line)
}
