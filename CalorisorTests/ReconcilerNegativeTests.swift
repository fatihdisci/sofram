//
//  ReconcilerNegativeTests.swift
//  CalorisorTests — regression coverage for unsafe partial food-name matches.
//


import XCTest
@testable import Calorisor

final class ReconcilerNegativeTests: XCTestCase {
    func testEveryShortWellEstablishedNameRejectsCompoundDerivatives() throws {
        let references = try TurkishFoodReference.load()
        XCTAssertGreaterThanOrEqual(references.count, 145, "The full reference database must be exercised")

        let shortNames = references.filter {
            $0.isWellEstablished && $0.name.count <= 5
        }
        XCTAssertFalse(shortNames.isEmpty)

        for reference in shortNames {
            for derivedName in [
                "\(reference.name)lu kek",
                "\(reference.name) salatası",
                "ızgara \(reference.name)",
            ] {
                let result = ReferenceReconciler.reconcile(
                    item: makeItem(name: derivedName),
                    in: references
                )

                XCTAssertEqual(
                    result.source,
                    .ai,
                    "\(derivedName) must not partially match \(reference.name)"
                )
                XCTAssertNil(result.referenceName)
            }
        }
    }

    func testPartialFoodNamesDoNotReceiveReferenceMatches() throws {
        let references = try TurkishFoodReference.load()

        for name in [
            "ızgara balık",
            "balık ekmek",
            "muzlu kek",
            "elmalı turta",
            "üzümlü kek",
        ] {
            let result = ReferenceReconciler.reconcile(item: makeItem(name: name), in: references)

            XCTAssertEqual(result.source, .ai, "\(name) should retain AI nutrition")
            XCTAssertNil(result.referenceName, "\(name) should not receive a reference match")
        }
    }

    func testBareEkmekDoesNotPartiallyMatchAnotherReference() throws {
        let referencesWithoutBread = try TurkishFoodReference.load().filter { $0.category != "ekmek" }
        let result = ReferenceReconciler.reconcile(
            item: makeItem(name: "ekmek"),
            in: referencesWithoutBread
        )

        XCTAssertEqual(result.source, .ai)
        XCTAssertNil(result.referenceName)
    }

    func testCayAliasMatchesSiyahCaySekersiz() throws {
        let result = try reconcile("çay")

        XCTAssertEqual(result.source, .reference)
        XCTAssertEqual(result.referenceName, "Siyah çay (şekersiz)")
    }

    func testMercimekNamesMatchMercimekCorbasi() throws {
        for name in ["mercimek çorbası", "kırmızı mercimek çorbası"] {
            let result = try reconcile(name)

            XCTAssertEqual(result.source, .reference)
            XCTAssertEqual(result.referenceName, "mercimek çorbası")
        }
    }

    func testReorderedTokensMatchMercimekCorbasi() throws {
        let result = try reconcile("çorbası mercimek")

        XCTAssertEqual(result.source, .reference)
        XCTAssertEqual(result.referenceName, "mercimek çorbası")
    }

    func testExactMuzMatchesMuz() throws {
        let result = try reconcile("Muz")

        XCTAssertEqual(result.source, .reference)
        XCTAssertEqual(result.referenceName, "Muz")
    }

    func testEveryParenthesizedReferenceHasBareAlias() throws {
        let references = try TurkishFoodReference.load()

        for reference in references where reference.name.contains("(") {
            let bareName = String(reference.name.prefix { $0 != "(" })
            let bareKey = String.Turkish.foodKey(bareName)
            let canonicalKey = String.Turkish.foodKey(reference.name)

            XCTAssertTrue(
                String.Turkish.aliases(for: bareKey).contains(canonicalKey),
                "Missing bare alias for \(reference.name)"
            )
        }
    }

    private func reconcile(_ name: String) throws -> ReferenceReconciler.ReconciledNutrition {
        ReferenceReconciler.reconcile(
            item: makeItem(name: name),
            in: try TurkishFoodReference.load()
        )
    }

    private func makeItem(name: String) -> VisionItem {
        VisionItem(
            name: name,
            nameEn: "",
            estimatedGrams: 100,
            householdUnit: "gram",
            householdQuantity: 100,
            calories: 321,
            proteinG: 7,
            carbsG: 60,
            fatG: 8,
            confidence: 0.8,
            note: nil
        )
    }
}
