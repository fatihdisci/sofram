//
//  Layout.swift
//  Calorisor — spacing, radius and motion constants from design-tokens.json
//

import SwiftUI

enum Layout {

    /// 4px base unit.
    static let spacingUnit: CGFloat = 4

    /// Raw spacing scale from design-tokens.json: 4·8·12·16·20·24·32.
    static let spacingScale: [CGFloat] = [4, 8, 12, 16, 20, 24, 32]

    enum Spacing {
        static let xs:   CGFloat = 4
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 12
        static let base: CGFloat = 16
        static let lg:   CGFloat = 20
        static let xl:   CGFloat = 24
        static let xxl:  CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 12          // controls (steppers, small buttons)
        static let card: CGFloat = 16             // standard cards
        static let raisedContainer: CGFloat = 24  // raised containers (ring bg, main card)
        static let pill: CGFloat = 999            // fully rounded
    }

    /// Motion durations (seconds) + spring params. Constants only — the actual
    /// micro-interactions (mikro-etkilesimler.md) are implemented in later phases.
    enum Motion {
        static let fast: Double = 0.15
        static let snap: Double = 0.20
        static let base: Double = 0.30
        static let slow: Double = 0.50
        static let springResponse: Double = 0.40
        static let springDamping: Double = 0.75
    }
}

extension Animation {
    /// Standard Sofra spring (response 0.4, damping 0.75) from the motion token block.
    static let sofraSpring = Animation.spring(
        response: Layout.Motion.springResponse,
        dampingFraction: Layout.Motion.springDamping
    )
}
