import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Could not open panel screenshot")
}
let height = min(380, image.height)
guard let crop = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: height)),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
    fatalError("Could not crop panel screenshot")
}
CGImageDestinationAddImage(destination, crop, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save glance screenshot") }
