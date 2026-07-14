//
//  TextLogInputPolicyTests.swift
//  CalorisorTests — text-entry character limit coverage.
//


import XCTest
@testable import Calorisor

final class TextLogInputPolicyTests: XCTestCase {
    func testTypedOrPastedTextIsLimitedToThreeHundredCharacters() {
        let input = String(repeating: "ö", count: 350)
        let limited = TextLogInputPolicy.limited(input)

        XCTAssertEqual(limited.count, 300)
        XCTAssertEqual(TextLogInputPolicy.maxCharacters, 300)
        XCTAssertEqual(TextLogInputPolicy.counterThreshold, 240)
    }

    func testShortTextIsUnchanged() {
        let input = "2 kepçe mercimek çorbası"

        XCTAssertEqual(TextLogInputPolicy.limited(input), input)
    }
}
