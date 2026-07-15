//
//  ImageDownscalerTests.swift
//  CalpTests — upload payload resizing and JPEG re-encoding coverage.
//


import CoreImage
import UIKit
import XCTest
@testable import Calp

final class ImageDownscalerTests: XCTestCase {
    func testLargeImageBecomesSmallerJPEGPayload() throws {
        let extent = CGRect(x: 0, y: 0, width: 4_000, height: 2_000)
        let randomImage = try XCTUnwrap(CIFilter(name: "CIRandomGenerator")?.outputImage)
            .cropped(to: extent)
        let cgImage = try XCTUnwrap(CIContext().createCGImage(randomImage, from: extent))
        let image = UIImage(cgImage: cgImage)
        let original = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        let payload = try XCTUnwrap(ImageDownscaler.jpegForUpload(original))
        let resized = try XCTUnwrap(UIImage(data: payload))

        XCTAssertLessThan(payload.base64EncodedString().count, original.base64EncodedString().count)
        XCTAssertLessThanOrEqual(max(resized.size.width, resized.size.height), ImageDownscaler.maxDimension)
        XCTAssertEqual(Array(payload.prefix(2)), [0xFF, 0xD8])
    }
}
