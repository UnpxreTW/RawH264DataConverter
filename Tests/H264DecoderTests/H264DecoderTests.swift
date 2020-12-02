import XCTest
@testable import H264Decoder

final class H264DecoderTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        var decoder = H264Decoder()
        decoder.setHandler { _ in
            
        }
        decoder.qnqueue(<#T##Raw H.264 Data##Data#>)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
