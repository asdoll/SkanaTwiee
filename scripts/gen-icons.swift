// Generates SkanaTwiee's icons: a purple field plus an original glyph.
//
// The glyph is a pixel-style chat bubble with a play triangle knocked out of it,
// a tail on the bottom-left and a 45-degree cut on the top-right. It sits in the
// same visual family as a streaming app's mark (purple field, white angular
// bubble) without reproducing any existing logo: no eye slits, no Twitch
// outline, a different silhouette.
//
//   background.png  1024x1024  full-bleed purple gradient (layered icon, back)
//   foreground.png  1024x1024  transparent, white glyph (layered icon, front)
//   startIcon.png    512x512   purple disc with the glyph, round, transparent
//                              outside the circle (the start-window icon)
//
// Run: swift /tmp/gen_icons.swift <output-directory>

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - palette

let purpleTop = CGColor(srgbRed: 0.678, green: 0.451, blue: 1.000, alpha: 1)   // #AD73FF
let purpleBottom = CGColor(srgbRed: 0.451, green: 0.208, blue: 0.941, alpha: 1) // #7335F0
let glyphWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

// MARK: - geometry

/// How much taller the glyph box is than the bubble itself, because of the tail.
let tailRatio: CGFloat = 1.16

/// The bubble outline, drawn in a box whose width is 1 and whose height is
/// `tailRatio` (the bubble is square; the tail takes the rest). Coordinates run
/// top-left to bottom-right.
///
/// The corner radii are proportional; `cut` is the 45-degree slice taken off the
/// top-right that gives the mark its pixel-art personality, and the tail hangs
/// off the bottom-left.
func bubblePath(box: CGRect) -> CGPath {
    let w = box.width
    let h = box.height / tailRatio        // the bubble's own height
    let r: CGFloat = 0.13 * w              // corner radius
    let cut: CGFloat = 0.17 * w            // top-right diagonal
    let tailX: CGFloat = 0.34 * w          // where the tail meets the bottom edge
    let tailTipY: CGFloat = tailRatio * h  // the bottom of the box
    // The tail's diagonal ends exactly where the bottom-left corner arc begins,
    // so the outline never doubles back on itself.
    let tailBaseX: CGFloat = r

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: box.minX + x, y: box.minY + y)
    }

    let path = CGMutablePath()
    path.move(to: p(r, 0))
    path.addLine(to: p(w - cut, 0))                       // top edge
    path.addLine(to: p(w, cut))                           // 45-degree cut
    path.addLine(to: p(w, h - r))                         // right edge
    path.addArc(tangent1End: p(w, h), tangent2End: p(w - r, h), radius: r)
    path.addLine(to: p(tailX, h))                         // bottom edge to the tail
    path.addLine(to: p(tailX, tailTipY))                  // tail: down
    path.addLine(to: p(tailBaseX, h))                     // tail: back up to the corner
    path.addArc(tangent1End: p(0, h), tangent2End: p(0, h - r), radius: r)
    path.addLine(to: p(0, r))                             // left edge
    path.addArc(tangent1End: p(0, 0), tangent2End: p(r, 0), radius: r)
    path.closeSubpath()
    return path
}

/// The play triangle that is knocked out of the bubble.
func playPath(box: CGRect) -> CGPath {
    let w = box.width
    let h = box.height / tailRatio         // the bubble's own height
    let cx: CGFloat = 0.40 * w             // left edge of the triangle
    let top: CGFloat = 0.28 * h
    let bottom: CGFloat = 0.72 * h
    let tipX: CGFloat = 0.77 * w

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: box.minX + x, y: box.minY + y)
    }

    let path = CGMutablePath()
    path.move(to: p(cx, top))
    path.addLine(to: p(tipX, (top + bottom) / 2))
    path.addLine(to: p(cx, bottom))
    path.closeSubpath()
    return path
}

/// The glyph bounding box inside a canvas of `size`, centred.
func glyphBox(size: CGFloat, widthFraction: CGFloat) -> CGRect {
    let w = size * widthFraction
    let h = w * tailRatio
    return CGRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h)
}

// MARK: - drawing

/// Fills `shape` with the brand gradient.
func fillGradient(_ ctx: CGContext, shape: CGPath, size: CGFloat) {
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space,
                              colors: [purpleTop, purpleBottom] as CFArray,
                              locations: [0, 1])!
    // Top-left to bottom-right, in the flipped (top-left origin) space.
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0),
                           options: [])
    ctx.restoreGState()
}

/// Fills the bubble with the triangle knocked out, in white.
func fillGlyph(_ ctx: CGContext, box: CGRect) {
    let path = CGMutablePath()
    path.addPath(bubblePath(box: box))
    path.addPath(playPath(box: box))
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setFillColor(glyphWhite)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
}

func makeContext(size: Int, opaque: Bool = false) -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue
                      : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: info)!
    // Work in top-left coordinates for the geometry above.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func writePNG(_ ctx: CGContext, to path: String) {
    guard let image = ctx.makeImage() else { fatalError("no image") }
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                     UTType.png.identifier as CFString,
                                                     1, nil) else {
        fatalError("no destination for \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(path)") }
    print("wrote \(path)")
}

// MARK: - the three files

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

/// Layered icon background: the purple field on its own, edge to edge, opaque.
do {
    let ctx = makeContext(size: 1024, opaque: true)
    let full = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    fillGradient(ctx, shape: CGPath(rect: full, transform: nil), size: 1024)
    writePNG(ctx, to: "\(outDir)/background.png")
}

/// Layered icon foreground: the glyph, transparent elsewhere. It stays inside
/// the middle of the canvas so the system's squircle mask never clips it.
do {
    let ctx = makeContext(size: 1024)
    fillGlyph(ctx, box: glyphBox(size: 1024, widthFraction: 0.54))
    writePNG(ctx, to: "\(outDir)/foreground.png")
}

/// Start-window icon: a purple disc with the glyph on it, round.
do {
    let size: CGFloat = 512
    let ctx = makeContext(size: Int(size))
    let disc = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
    fillGradient(ctx, shape: disc, size: size)
    fillGlyph(ctx, box: glyphBox(size: size, widthFraction: 0.54))
    writePNG(ctx, to: "\(outDir)/startIcon.png")
}
