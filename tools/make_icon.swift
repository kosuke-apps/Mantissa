#!/usr/bin/env swift
// Draws the Mantissa app icon: a radical sign over the dotted empty box that marks an unfilled slot in the editor.
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
  let radical: CGColor
  let box: CGColor
  let shadow: CGColor
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha)
}

let variants = [
  Variant(
    name: "light", backgroundTop: rgb(0xE8506A), backgroundBottom: rgb(0xA3203A), radical: rgb(0xFFFFFF),
    box: rgb(0xFFFFFF, 0.78), shadow: rgb(0x4A0A18, 0.35)),
  Variant(
    name: "dark", backgroundTop: rgb(0x2B1519), backgroundBottom: rgb(0x120709), radical: rgb(0xFF6B7D),
    box: rgb(0xFF6B7D, 0.6), shadow: rgb(0x000000, 0.5)),
  Variant(
    name: "tinted", backgroundTop: rgb(0x000000), backgroundBottom: rgb(0x000000), radical: rgb(0xFFFFFF),
    box: rgb(0xFFFFFF, 0.7), shadow: rgb(0x000000, 0.0)),
]

// The radical sign: a short rising tick, the long fall, the long rise, then the bar over the radicand.
// Coordinates are measured from the top left.
let radicalPoints = [
  CGPoint(x: 185, y: 600), CGPoint(x: 290, y: 548), CGPoint(x: 410, y: 815), CGPoint(x: 545, y: 285),
  CGPoint(x: 850, y: 285),
]

func render(_ v: Variant) -> CGImage {
  let space = CGColorSpaceCreateDeviceRGB()
  let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  // Draw from the top left, like the coordinates above.
  ctx.translateBy(x: 0, y: size)
  ctx.scaleBy(x: 1, y: -1)

  let gradient = CGGradient(colorsSpace: space, colors: [v.backgroundTop, v.backgroundBottom] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])

  // The empty box under the bar: dashed, like the placeholder in the editor.
  let box = CGRect(x: 590, y: 415, width: 215, height: 290)
  ctx.setStrokeColor(v.box)
  ctx.setLineWidth(30)
  ctx.setLineDash(phase: 0, lengths: [44, 34])
  ctx.setLineCap(.round)
  ctx.addPath(CGPath(roundedRect: box, cornerWidth: 34, cornerHeight: 34, transform: nil))
  ctx.strokePath()
  ctx.setLineDash(phase: 0, lengths: [])

  ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 34, color: v.shadow)
  ctx.setStrokeColor(v.radical)
  ctx.setLineWidth(64)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)
  ctx.addLines(between: radicalPoints)
  ctx.strokePath()

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
