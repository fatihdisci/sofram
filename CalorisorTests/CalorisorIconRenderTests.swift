//
//  CalorisorIconRenderTests.swift
//  CalorisorTests — deterministic geometry coverage for the custom icon family.
//
//  These are pure-geometry checks (SwiftUI `Path` math, no running app / no
//  snapshot infra): every `CalorisorIcon` must have primitives, must render a
//  non-empty path that stays inside its target rect, and the minimal SVG path
//  parser must handle exactly the command set the icons use.
//

import XCTest
import SwiftUI
@testable import Calorisor

final class CalorisorIconRenderTests: XCTestCase {

    private let rect = CGRect(x: 0, y: 0, width: 96, height: 96)

    // MARK: Catalog

    func testEveryIconHasPrimitives() {
        for icon in CalorisorIcon.allCases {
            XCTAssertFalse(icon.primitives.isEmpty, "\(icon.rawValue) has no drawing primitives")
        }
    }

    func testNewProductIconsArePresent() {
        let cases = Set(CalorisorIcon.allCases)
        XCTAssertTrue(cases.contains(.capture))
        XCTAssertTrue(cases.contains(.mealNote))
        XCTAssertTrue(cases.contains(.emptyPlate))
    }

    // MARK: Rendering

    func testEveryIconRendersNonEmptyPath() {
        for icon in CalorisorIcon.allCases {
            let path = CalorisorIconShape(icon: icon).path(in: rect)
            XCTAssertFalse(path.isEmpty, "\(icon.rawValue) rendered an empty path")
            XCTAssertGreaterThan(path.boundingRect.width, 0, "\(icon.rawValue) has zero width")
            XCTAssertGreaterThan(path.boundingRect.height, 0, "\(icon.rawValue) has zero height")
        }
    }

    func testEveryIconStaysWithinItsRect() {
        // The 24×24 source is fit uniformly into `rect`; nothing should spill
        // meaningfully out. Tolerance is generous (a curve's control-point
        // bounding box can nudge slightly past on-curve extremes) — the goal is
        // to catch gross geometry errors (e.g. a missing scale), not sub-pixel drift.
        let tolerance: CGFloat = 2.0
        for icon in CalorisorIcon.allCases {
            let box = CalorisorIconShape(icon: icon).path(in: rect).boundingRect
            XCTAssertGreaterThanOrEqual(box.minX, rect.minX - tolerance, "\(icon.rawValue) spills left")
            XCTAssertGreaterThanOrEqual(box.minY, rect.minY - tolerance, "\(icon.rawValue) spills top")
            XCTAssertLessThanOrEqual(box.maxX, rect.maxX + tolerance, "\(icon.rawValue) spills right")
            XCTAssertLessThanOrEqual(box.maxY, rect.maxY + tolerance, "\(icon.rawValue) spills bottom")
        }
    }

    func testIconsRenderAcrossUISizesWithoutCollapsing() {
        // 18 / 20 / 24 / 32 pt are the sizes the family is used at; the path must
        // stay proportional (non-empty, positive extent) at each.
        for size: CGFloat in [18, 20, 24, 32] {
            let square = CGRect(x: 0, y: 0, width: size, height: size)
            for icon in CalorisorIcon.allCases {
                let box = CalorisorIconShape(icon: icon).path(in: square).boundingRect
                XCTAssertGreaterThan(box.width, 0, "\(icon.rawValue) collapsed at \(size)pt")
                XCTAssertGreaterThan(box.height, 0, "\(icon.rawValue) collapsed at \(size)pt")
            }
        }
    }

    // MARK: SVG path parser (only the commands the icons use: M L H V C S Z)

    func testParserBuildsClosedSquareFromLineCommands() {
        var path = Path()
        SVGPath.append("M2 2 H22 V22 H2 Z", to: &path, scale: 1, offset: .zero)
        let box = path.boundingRect
        XCTAssertEqual(box.minX, 2, accuracy: 0.001)
        XCTAssertEqual(box.minY, 2, accuracy: 0.001)
        XCTAssertEqual(box.maxX, 22, accuracy: 0.001)
        XCTAssertEqual(box.maxY, 22, accuracy: 0.001)
    }

    func testParserTreatsExtraMoveToPairsAsLineTo() {
        // "M a b c d" — the second coordinate pair is an implicit lineTo.
        var path = Path()
        SVGPath.append("M0 0 10 20", to: &path, scale: 1, offset: .zero)
        XCTAssertEqual(path.boundingRect.maxX, 10, accuracy: 0.001)
        XCTAssertEqual(path.boundingRect.maxY, 20, accuracy: 0.001)
    }

    func testParserAppliesScaleAndOffset() {
        var path = Path()
        SVGPath.append("M0 0 H10", to: &path, scale: 2, offset: CGPoint(x: 5, y: 3))
        let box = path.boundingRect
        XCTAssertEqual(box.minX, 5, accuracy: 0.001)   // 0*2 + 5
        XCTAssertEqual(box.maxX, 25, accuracy: 0.001)  // 10*2 + 5
        XCTAssertEqual(box.minY, 3, accuracy: 0.001)
    }

    func testParserHandlesRelativeCubicChains() {
        // The new .capture / .mealNote bodies use chained relative cubics; a
        // relative-cubic path must produce bounded, finite geometry.
        var path = Path()
        SVGPath.append("M4 4c2 0 4 2 4 4s-2 4-4 4-4-2-4-4 2-4 4-4Z", to: &path, scale: 1, offset: .zero)
        XCTAssertFalse(path.isEmpty)
        let box = path.boundingRect
        XCTAssertTrue(box.width.isFinite && box.height.isFinite)
        XCTAssertGreaterThan(box.width, 0)
    }
}
