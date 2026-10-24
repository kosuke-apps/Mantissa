// Draws the Mantissa app icon: a "1" and a decimal point followed by digits that fade away, the part of a number that gives the
// app its name.
//
//   swift tools/make_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
//
// Writes icon-light.png, icon-dark.png and icon-tinted.png (1024 x 1024, no transparency, no text) and the matching
// Contents.json. iOS rounds the corners itself.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024

struct Variant {
  let name: String
  let backgroundTop: CGColor
  let backgroundBottom: CGColor
  let mark: CGColor
  let shadow: CGColor
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha)
}

let variants = [
  Variant(
    name: "light", backgroundTop: rgb(0x1AA79E), backgroundBottom: rgb(0x0B5F63), mark: rgb(0xFFFFFF),
    shadow: rgb(0x032A2C, 0.35)),
  Variant(
    name: "dark", backgroundTop: rgb(0x10302F), backgroundBottom: rgb(0x071413), mark: rgb(0x4FD1C5),
    shadow: rgb(0x000000, 0.5)),
  Variant(
    name: "tinted", backgroundTop: rgb(0x000000), backgroundBottom: rgb(0x000000), mark: rgb(0xFFFFFF),
    shadow: rgb(0x000000, 0.0)),
]

// The "1": a short flag falling to the left of the top of a straight stem. Coordinates are measured from the top left.
let onePoints = [CGPoint(x: 205, y: 395), CGPoint(x: 335, y: 320), CGPoint(x: 335, y: 705)]

// The point, then the digits after it, each smaller and fainter than the last: centre, radius and opacity.
let dots: [(x: CGFloat, y: CGFloat, radius: CGFloat, opacity: CGFloat)] = [
  (465, 690, 46, 1.0), (590, 690, 37, 0.85), (698, 690, 29, 0.65), (790, 690, 21, 0.45), (866, 690, 14, 0.28),
]

func render(_ v: Variant) -> CGImage {
  let space = CGColorSpaceCreateDeviceRGB()
  let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  // Draw from the top left, like the coordinates above.
  ctx.translateBy(x: 0, y: size)
  ctx.scaleBy(x: 1, y: -1)

  let gradient = CGGradient(
    colorsSpace: space, colors: [v.backgroundTop, v.backgroundBottom] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])

  ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 34, color: v.shadow)
  ctx.setStrokeColor(v.mark)
  ctx.setLineWidth(84)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)
  ctx.addLines(between: onePoints)
  ctx.strokePath()

  for dot in dots {
    ctx.setFillColor(v.mark.copy(alpha: dot.opacity)!)
    ctx.fillEllipse(
      in: CGRect(x: dot.x - dot.radius, y: dot.y - dot.radius, width: dot.radius * 2, height: dot.radius * 2))
  }

  return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let output = URL(fileURLWithPath: outputPath, isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for variant in variants {
  writePNG(render(variant), to: output.appendingPathComponent("icon-\(variant.name).png"))
}

let contents = """
  {
    "images" : [
      { "filename" : "icon-light.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
      {
        "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
        "filename" : "icon-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
      },
      {
        "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
        "filename" : "icon-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
      }
    ],
    "info" : { "author" : "xcode", "version" : 1 }
  }
  """
try contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote 3 icons to \(output.path)")
