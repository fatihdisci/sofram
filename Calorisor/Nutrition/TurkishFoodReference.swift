//
//  TurkishFoodReference.swift
//  Calorisor — lazy loader for the bundled Türkiye food reference DB.
//
//  Source: `Calorisor/Resources/turkish_food_reference.json` (Phase B3 prep).
//  Loader is pure data plumbing — no UI, no matching. The reconciler in
//  `ReferenceReconciler` is what decides whether a VisionItem should fall
//  back to AI numbers or use DB-derived values.
//
//  Threading
//  ---------
//  The first call to `load()` performs the JSON decode and populates both
//  the foods array and the normalized lookup index. Subsequent calls hit
//  the cached structures. We use a serial queue + double-checked locking
//  to keep the first-call cost one-shot and race-free.
//
//  Graceful degradation
//  --------------------
//  `load()` throws on missing-file or decode-failure (e.g. test bundles
//  without the resource). `index()` returns `[:]` in that case so the
//  reconciler's "no match" path triggers and AI values are preserved.
//

import Foundation

enum TurkishFoodReference {

    enum LoadError: Error, CustomStringConvertible {
        case fileMissing(name: String, ext: String)
        case decodingFailed(underlying: Error)

        var description: String {
            switch self {
            case .fileMissing(let n, let e):
                return "turkish_food_reference.\(e) not found in main bundle (\(n))"
            case .decodingFailed(let err):
                return "Failed to decode turkish_food_reference.json: \(err)"
            }
        }
    }

    private static let bundleName = "turkish_food_reference"
    private static let ext = "json"
    private static let queue = DispatchQueue(label: "calorisor.turkish_food_reference.cache")

    private static var cachedFoods: [FoodReference]?
    private static var cachedIndex: [String: FoodReference]?

    private final class BundleMarker {}

    // MARK: - Public API

    /// Decode the bundled JSON. Cached after the first successful call.
    /// Throws `LoadError.fileMissing` if the resource isn't in the bundle
    /// (e.g. running tests without the host app), or `LoadError.decodingFailed`
    /// if the schema drifts.
    static func load() throws -> [FoodReference] {
        if let cached = cachedFoods { return cached }
        return try queue.sync {
            if let cached = cachedFoods { return cached }
            guard let url = resourceURL() else {
                throw LoadError.fileMissing(name: bundleName, ext: ext)
            }
            do {
                let data = try Data(contentsOf: url)
                let payload = try JSONDecoder().decode(FoodReferencePayload.self, from: data)
                cachedFoods = payload.foods
                cachedIndex = buildIndex(from: payload.foods)
                return payload.foods
            } catch let err as LoadError {
                throw err
            } catch {
                throw LoadError.decodingFailed(underlying: error)
            }
        }
    }

    /// Lowercase + diacritic-folded name → food lookup table. Built once on
    /// first `load()` and cached. Returns `[:]` if the bundle is missing or
    /// the decode fails — the reconciler treats this as "no reference data"
    /// and falls back to AI numbers.
    static func index() -> [String: FoodReference] {
        if let cached = cachedIndex { return cached }
        _ = try? load()
        return cachedIndex ?? [:]
    }

    /// Convenience: return the full food array (same shape as `load()` but
    /// without throwing). Returns `[]` on bundle-missing / decode-fail.
    /// Use this when you want to iterate every food (e.g. the reconciler
    /// path), not look up by name.
    static func foods() -> [FoodReference] {
        if let cached = cachedFoods { return cached }
        _ = try? load()
        return cachedFoods ?? []
    }

    /// Test seam: install an in-memory dataset so XCTest can exercise
    /// specific foods without depending on the bundle resource.
    /// Returns a `ResetHandle` token — call `restore()` to put the original
    /// bundle-backed cache back in place.
    @discardableResult
    static func installForTesting(_ foods: [FoodReference]) -> ResetHandle {
        queue.sync {
            cachedFoods = foods
            cachedIndex = buildIndex(from: foods)
            return ResetHandle()
        }
    }

    final class ResetHandle {
        fileprivate init() {}
        func restore() {
            TurkishFoodReference.reset()
        }
    }

    /// Drop the cache. Production code does not call this; tests use
    /// `installForTesting(_:)` instead.
    static func reset() {
        queue.sync {
            cachedFoods = nil
            cachedIndex = nil
        }
    }

    // MARK: - Resource lookup

    /// In app runs the JSON is in `Bundle.main`; in XCTest it can be exposed via
    /// the app module bundle. Probe both plus loaded bundles so `load()` remains
    /// the single production/test entry point.
    static func resourceURL() -> URL? {
        let candidates = [Bundle.main, Bundle(for: BundleMarker.self)] + Bundle.allBundles + Bundle.allFrameworks
        var seen = Set<String>()

        for bundle in candidates where seen.insert(bundle.bundlePath).inserted {
            if let url = bundle.url(forResource: bundleName, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    // MARK: - Index builder

    /// Build the lowercase + diacritic-folded name → food lookup table.
    /// Uses the Turkish `name` as the primary key; the `name_en` is a
    /// secondary fallback the reconciler can probe if the Turkish name
    /// doesn't hit.
    ///
    /// First-wins on collisions — the JSON has 4 foods whose Turkish name
    /// and English name normalize to the same key ("menemen", "su boregi",
    /// "kol boregi", "sigara boregi"). Keeping the first value makes the
    /// cache deterministic if future aliases collide.
    static func buildIndex(from foods: [FoodReference]) -> [String: FoodReference] {
        var out: [String: FoodReference] = [:]
        out.reserveCapacity(foods.count * 2)
        for food in foods {
            let keyTr = String.Turkish.foodKey(food.name)
            if !keyTr.isEmpty && out[keyTr] == nil { out[keyTr] = food }
            let keyEn = String.Turkish.foodKey(food.nameEn)
            if !keyEn.isEmpty && out[keyEn] == nil { out[keyEn] = food }
        }
        return out
    }
}