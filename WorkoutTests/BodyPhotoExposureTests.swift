import XCTest
@testable import Workout

final class BodyPhotoExposureTests: XCTestCase {
    private func solidImage(gray: CGFloat) -> CGImage {
        let size = CGSize(width: 80, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(white: gray / 255.0, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.cgImage!
    }

    func testFlagsDarkPhoto() {
        let warnings = BodyPhotoQualityAnalyzer.exposureWarnings(from: solidImage(gray: 20))
        XCTAssertTrue(warnings.contains { $0.contains("偏暗") })
    }

    func testFlagsOverexposedPhoto() {
        let warnings = BodyPhotoQualityAnalyzer.exposureWarnings(from: solidImage(gray: 250))
        XCTAssertTrue(warnings.contains { $0.contains("过亮") })
    }

    func testAcceptsWellExposedPhoto() {
        let warnings = BodyPhotoQualityAnalyzer.exposureWarnings(from: solidImage(gray: 128))
        XCTAssertTrue(warnings.isEmpty)
    }
}
