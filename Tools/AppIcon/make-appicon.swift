#!/usr/bin/env swift
//
//  make-appicon.swift
//
//  Regenerates the ScribeKit application icon from the brand mark in
//  `docs/images/scribekit-logo2.png`.
//
//  The brand mark is already an app-icon composition: a dark rounded square
//  holding the document, quill and waveform, with no wordmark. This script
//  trims the mark's white outline, places it on the standard macOS icon grid
//  (an 824 pt body centred on a 1024 pt canvas) and writes the ten
//  representations the asset catalog declares.
//
//  Usage, from the repository root:
//      swift Tools/AppIcon/make-appicon.swift
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appending(path: "docs/images/scribekit-logo2.png")
let destination = root.appending(path: "ScribeKit/Assets.xcassets/AppIcon.appiconset")

/// The mark's opaque bounds inside the source image, inset past its white
/// outline so the icon carries the artwork alone.
let markOriginX = 48
let markOriginY = 29
let markWidth = 688
let markHeight = 667

/// Apple's macOS icon grid: an 824 pt body centred on a 1024 pt canvas.
let canvasSide = 1024.0
let bodySide = 824.0

let colourSpace = CGColorSpace(name: CGColorSpace.sRGB)!

guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let mark = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fatalError("cannot read \(source.path)")
}

guard let cropped = mark.cropping(to: CGRect(x: markOriginX, y: markOriginY,
                                             width: markWidth, height: markHeight)) else {
    fatalError("cannot crop the brand mark")
}

/// Renders the icon at `side` points.
func render(side: Double) -> CGImage {
    let context = CGContext(data: nil,
                            width: Int(side), height: Int(side),
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: colourSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    let body = side * bodySide / canvasSide
    let inset = (side - body) / 2
    context.draw(cropped, in: CGRect(x: inset, y: inset, width: body, height: body))
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    guard let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(out, image, nil)
    guard CGImageDestinationFinalize(out) else { fatalError("cannot finalize \(url.path)") }
}

/// The asset catalog's macOS slots: point size and scale.
let slots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)
]

for slot in slots {
    let pixels = Double(slot.points * slot.scale)
    let name = slot.scale == 1 ? "icon_\(slot.points)x\(slot.points).png"
                               : "icon_\(slot.points)x\(slot.points)@2x.png"
    write(render(side: pixels), to: destination.appending(path: name))
    print("wrote \(name) (\(Int(pixels))px)")
}
