//
//  CalpIcon.swift
//  Calp — custom line icons as SwiftUI Shape views.
//
//  Approach (see PHASE_1_NOTES.md): the original SVGs are simple single-color
//  stroked line icons (24×24 viewBox, 1.5px stroke, round caps/joins) using only
//  M/L/H/V/C/S/Z commands + <circle>/<ellipse> — no elliptical arcs. Rather than
//  rasterize or ship PDFs, each icon's geometry is embedded verbatim and parsed
//  into a SwiftUI `Path` by a tiny SVG-path parser below.
//
//  Why Shape views (not PDF imagesets):
//   • true vector, tints via `.foregroundStyle` (the SVG `currentColor` contract),
//   • crisp 1.5px stroke that scales proportionally with the icon size,
//   • and — critically for later phases — the portion icons need a draw-on / fill
//     animation (mikro-etkilesimler.md), which `.trim`/stroke on a Shape supports
//     natively but a rasterized imageset cannot.
//
//  This file is intentionally dependency-free (SwiftUI only) so the geometry can be
//  unit-rendered on macOS by tools/RenderIcons during development.
//

import SwiftUI

// MARK: - Icon catalog

enum CalpIcon: String, CaseIterable, Identifiable {
    case kepce          // ladle
    case tabak          // plate
    case cayBardagi     // tea glass
    case ekmekDilimi    // bread slice
    case kase           // bowl
    case kasik          // spoon
    case calp      // shared table (top-down) — brand mark
    case tencere        // pot
    case bugun          // today tab: plate + morning rays
    case gecmis         // history tab: notebook calendar
    case ayarlar        // settings tab: low flame

    // Product-defining action icons (see VISUAL_DIFFERENTIATION_NOTES.md §D).
    case capture        // photo meal capture: camera whose lens is a plate
    case mealNote       // text meal logging: a note/menu card with lines
    case emptyPlate     // empty food log: plate rim with an empty centre line

    var id: String { rawValue }

    /// Drawing primitives in the 0…24 SVG user space.
    var primitives: [CalpIconPrimitive] {
        switch self {
        case .kepce:
            return [
                .path("M9 10.5c0 2.49 1.79 4.5 4 4.5s4-2.01 4-4.5-1.79-4.5-4-4.5-4 2.01-4 4.5Z"),
                .path("M9.6 13.8 4 19.4"),
                .path("M3.3 20.7c.5.5 1.3.5 1.8 0l.6-.6c.5-.5.5-1.3 0-1.8-.5-.5-1.3-.5-1.8 0l-.6.6c-.5.5-.5 1.3 0 1.8Z"),
            ]
        case .tabak:
            return [
                .circle(cx: 12, cy: 12, r: 8.5),
                .circle(cx: 12, cy: 12, r: 5),
            ]
        case .cayBardagi:
            return [
                .path("M8 4c0 3-1.5 4.2-1.5 7.5C6.5 15.6 8.9 19 12 19s5.5-3.4 5.5-7.5C17.5 8.2 16 7 16 4"),
                .path("M6.3 4h11.4"),
                .path("M9.5 19.5h5"),
            ]
        case .ekmekDilimi:
            return [
                .path("M4 13c0-4.5 3.6-8 8-8s8 3.5 8 8v4.5c0 1-.8 1.5-1.5 1.5h-13c-.7 0-1.5-.5-1.5-1.5V13Z"),
                .path("M8.5 13.5c.6-.8 1.4-.8 2 0 .6.8 1.4.8 2 0 .6-.8 1.4-.8 2 0 .6.8 1.4.8 2 0"),
            ]
        case .kase:
            return [
                .path("M4 11h16"),
                .path("M4 11c0 4.5 3.6 8 8 8s8-3.5 8-8"),
                .path("M9 11c0-1.4.7-2 1.6-2h2.8c.9 0 1.6.6 1.6 2"),
            ]
        case .kasik:
            return [
                .ellipse(cx: 12, cy: 7, rx: 3.2, ry: 4),
                .path("M12 11v10"),
            ]
        case .calp:
            return [
                .circle(cx: 12, cy: 12, r: 9.5),
                .circle(cx: 12, cy: 6.3, r: 1.6),
                .circle(cx: 17.7, cy: 12, r: 1.6),
                .circle(cx: 12, cy: 17.7, r: 1.6),
                .circle(cx: 6.3, cy: 12, r: 1.6),
            ]
        case .tencere:
            return [
                .path("M5 10h14v4.5c0 2.8-2.2 5-5 5h-4c-2.8 0-5-2.2-5-5V10Z"),
                .path("M3 10h18"),
                .path("M2.5 8.7 5 10"),
                .path("M21.5 8.7 19 10"),
                .path("M9.5 10V7.5"),
                .path("M14.5 10V7.5"),
            ]
        case .bugun:
            return [
                .circle(cx: 12, cy: 13.5, r: 6.5),
                .path("M12 3v2"),
                .path("M5.5 5.5 7 7"),
                .path("M18.5 5.5 17 7"),
                .path("M7.5 15.5h9"),
            ]
        case .gecmis:
            return [
                .path("M6 4.5h12c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H6c-1.1 0-2-.9-2-2v-12c0-1.1.9-2 2-2Z"),
                .path("M8 3v3"),
                .path("M16 3v3"),
                .path("M7.5 10h9"),
                .path("M7.5 13.5h9"),
                .path("M7.5 17h6"),
            ]
        case .ayarlar:
            return [
                .path("M12 3c.8 3-1 4.2-1 6.2 0 1 .7 1.8 1.7 2.4-.2-1.6.8-2.8 2-4 2.2 1.9 3.3 4.2 3.3 6.6 0 3.5-2.7 6.2-6 6.2s-6-2.7-6-6.2c0-3 1.8-5.7 5-8.1-.5 2.4.2 3.6 1.4 4.7C10.5 6 11.7 4.6 12 3Z"),
                .path("M12 13c1.4 1.1 2 2.2 2 3.3 0 1.2-.9 2.2-2 2.2s-2-1-2-2.2c0-1.1.6-2.2 2-3.3Z"),
            ]
        case .capture:
            // Camera body + a small viewfinder hump; the lens is a plate
            // (double concentric circle, echoing `.tabak`) so "capture" reads
            // as "capture a plate", not a generic camera.
            return [
                .path("M8.7 6.5 9.6 5c.19-.31.53-.5.9-.5h3c.37 0 .71.19.9.5l.9 1.5"),
                .path("M4.5 6.5h15c1.1 0 2 .9 2 2v8.5c0 1.1-.9 2-2 2h-15c-1.1 0-2-.9-2-2V8.5c0-1.1.9-2 2-2Z"),
                .circle(cx: 12, cy: 13, r: 3.3),
                .circle(cx: 12, cy: 13, r: 1.3),
            ]
        case .mealNote:
            // A note / menu card with three text lines — the written-word
            // counterpart to the photo capture.
            return [
                .path("M6 4h12c.55 0 1 .45 1 1v14c0 .55-.45 1-1 1H6c-.55 0-1-.45-1-1V5c0-.55.45-1 1-1Z"),
                .path("M8.5 9h7"),
                .path("M8.5 12.5h7"),
                .path("M8.5 16h4.5"),
            ]
        case .emptyPlate:
            // A plate rim with a single empty centre line — "nothing logged
            // yet". Distinct from `.tabak` (which has a full inner rim).
            return [
                .circle(cx: 12, cy: 12, r: 8.5),
                .path("M9 12h6"),
            ]
        }
    }
}

enum CalpIconPrimitive {
    case path(String)                                             // SVG path `d`, 0…24 space
    case circle(cx: CGFloat, cy: CGFloat, r: CGFloat)
    case ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat)
}

// MARK: - Shape

/// A `Shape` built from a `CalpIcon`'s primitives, scaled to fill `rect`.
/// Stroke it (don't fill) — these are line icons.
struct CalpIconShape: Shape {
    let icon: CalpIcon

    func path(in rect: CGRect) -> Path {
        // The source viewBox is a 24×24 square; fit it into `rect` uniformly.
        let side = min(rect.width, rect.height)
        let scale = side / 24
        let offset = CGPoint(
            x: rect.minX + (rect.width - side) / 2,
            y: rect.minY + (rect.height - side) / 2
        )
        var path = Path()
        for primitive in icon.primitives {
            switch primitive {
            case .path(let d):
                SVGPath.append(d, to: &path, scale: scale, offset: offset)
            case .circle(let cx, let cy, let r):
                path.addEllipse(in: ellipseRect(cx: cx, cy: cy, rx: r, ry: r, scale: scale, offset: offset))
            case .ellipse(let cx, let cy, let rx, let ry):
                path.addEllipse(in: ellipseRect(cx: cx, cy: cy, rx: rx, ry: ry, scale: scale, offset: offset))
            }
        }
        return path
    }

    private func ellipseRect(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat,
                             scale: CGFloat, offset: CGPoint) -> CGRect {
        CGRect(x: offset.x + (cx - rx) * scale,
               y: offset.y + (cy - ry) * scale,
               width: 2 * rx * scale,
               height: 2 * ry * scale)
    }
}

// MARK: - View

/// Renders a `CalpIcon` at `size` points, stroked with a proportional 1.5px line
/// (relative to the 24pt source). Tint with `.foregroundStyle(...)`.
struct CalpIconView: View {
    let icon: CalpIcon
    var size: CGFloat = 24
    /// Source stroke width at 24pt; scales with `size`.
    var lineWidth: CGFloat = 1.5

    var body: some View {
        CalpIconShape(icon: icon)
            .stroke(style: StrokeStyle(lineWidth: lineWidth * size / 24,
                                       lineCap: .round,
                                       lineJoin: .round))
            .frame(width: size, height: size)
    }
}

// MARK: - Minimal SVG path parser
//
// Supports exactly what these 8 icons use: M/m L/l H/h V/v C/c S/s Z/z.
// (No quadratic, no elliptical-arc — verified against the source SVGs.)

enum SVGPath {

    private enum Token {
        case cmd(Character)
        case num(CGFloat)
    }

    static func append(_ d: String, to path: inout Path, scale: CGFloat, offset: CGPoint) {
        let tokens = tokenize(d)
        var index = 0
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint? = nil       // for S/s reflection; nil unless prev was C/S
        var command: Character = " "

        func nextNum() -> CGFloat? {
            guard index < tokens.count, case .num(let v) = tokens[index] else { return nil }
            index += 1
            return v
        }
        func abs(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: offset.x + x * scale, y: offset.y + y * scale)
        }
        func rel(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: current.x + dx * scale, y: current.y + dy * scale)
        }

        while index < tokens.count {
            if case .cmd(let c) = tokens[index] {
                command = c
                index += 1
            }
            let isRelative = command.isLowercase
            let upper = Character(command.uppercased())

            switch upper {
            case "M":
                guard let x = nextNum(), let y = nextNum() else { return }
                current = isRelative ? rel(x, y) : abs(x, y)
                path.move(to: current)
                subpathStart = current
                lastControl = nil
                // Subsequent implicit coordinate pairs after M are treated as L/l.
                command = isRelative ? "l" : "L"

            case "L":
                guard let x = nextNum(), let y = nextNum() else { return }
                current = isRelative ? rel(x, y) : abs(x, y)
                path.addLine(to: current)
                lastControl = nil

            case "H":
                guard let x = nextNum() else { return }
                current = isRelative
                    ? CGPoint(x: current.x + x * scale, y: current.y)
                    : CGPoint(x: offset.x + x * scale, y: current.y)
                path.addLine(to: current)
                lastControl = nil

            case "V":
                guard let y = nextNum() else { return }
                current = isRelative
                    ? CGPoint(x: current.x, y: current.y + y * scale)
                    : CGPoint(x: current.x, y: offset.y + y * scale)
                path.addLine(to: current)
                lastControl = nil

            case "C":
                guard let x1 = nextNum(), let y1 = nextNum(),
                      let x2 = nextNum(), let y2 = nextNum(),
                      let x = nextNum(), let y = nextNum() else { return }
                let c1 = isRelative ? rel(x1, y1) : abs(x1, y1)
                let c2 = isRelative ? rel(x2, y2) : abs(x2, y2)
                let end = isRelative ? rel(x, y) : abs(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastControl = c2

            case "S":
                guard let x2 = nextNum(), let y2 = nextNum(),
                      let x = nextNum(), let y = nextNum() else { return }
                let c2 = isRelative ? rel(x2, y2) : abs(x2, y2)
                let end = isRelative ? rel(x, y) : abs(x, y)
                // First control = reflection of previous control about the current point.
                let c1: CGPoint
                if let lc = lastControl {
                    c1 = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                } else {
                    c1 = current
                }
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastControl = c2

            case "Z":
                path.closeSubpath()
                current = subpathStart
                lastControl = nil

            default:
                // Unknown/unsupported command — advance to avoid an infinite loop.
                index += 1
            }
        }
    }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(d)
        let n = chars.count
        var i = 0

        func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }

        while i < n {
            let c = chars[i]
            if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" {
                i += 1
                continue
            }
            if c.isLetter {
                tokens.append(.cmd(c))
                i += 1
                continue
            }
            // Number: optional sign, digits, at most one dot (a second dot starts a new
            // number, e.g. "0.5.5" → 0.5, 0.5), optional exponent.
            var j = i
            if chars[j] == "+" || chars[j] == "-" { j += 1 }
            var seenDot = false
            while j < n {
                let d = chars[j]
                if isDigit(d) {
                    j += 1
                } else if d == "." && !seenDot {
                    seenDot = true
                    j += 1
                } else if d == "e" || d == "E" {
                    j += 1
                    if j < n && (chars[j] == "+" || chars[j] == "-") { j += 1 }
                } else {
                    break
                }
            }
            if j > i, let value = Double(String(chars[i..<j])) {
                tokens.append(.num(CGFloat(value)))
                i = j
            } else {
                i += 1 // not a parseable number; skip
            }
        }
        return tokens
    }
}

#if DEBUG

/// DEBUG-only internal catalog for eyeballing the whole family — every icon at
/// 18/24/32pt, over both backgrounds, in the primary/muted/accent tints. This
/// is a `#Preview` only; it is never wired into user-facing navigation.
struct CalpIconGallery: View {
    private let sizes: [CGFloat] = [18, 24, 32]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                row(scheme: .light)
                row(scheme: .dark)
            }
            .padding()
        }
    }

    private func row(scheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scheme == .light ? "Light" : "Dark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CalpIcon.allCases) { icon in
                    VStack(spacing: 8) {
                        // Three sizes, primary tint.
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(sizes, id: \.self) { size in
                                CalpIconView(icon: icon, size: size)
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                        // Muted + accent tints at 24pt.
                        HStack(spacing: 10) {
                            CalpIconView(icon: icon, size: 24)
                                .foregroundStyle(Color.textMuted)
                            CalpIconView(icon: icon, size: 24)
                                .foregroundStyle(Color.accentFill)
                        }
                        Text(icon.rawValue)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .background(Color.bgPage, in: RoundedRectangle(cornerRadius: 16))
        .environment(\.colorScheme, scheme)
    }
}

#Preview("Calp icon gallery") {
    CalpIconGallery()
}
#endif
