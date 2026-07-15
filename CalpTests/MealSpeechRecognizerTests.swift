//
//  MealSpeechRecognizerTests.swift
//  CalpTests — voice-input (SF-EX03) locale + state coverage.
//
//  The audio/recognition pipeline needs a device and user permission, so it
//  can't be exercised in a unit test. What we *can* pin down deterministically
//  is the language selection (which locale the recognizer is built for) and the
//  idle/listening state contract the view relies on.
//

import XCTest
@testable import Calp

@MainActor
final class MealSpeechRecognizerTests: XCTestCase {

    private func withAppLanguage(_ lang: AppLanguage, _ body: () -> Void) {
        let previous = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
        UserDefaults.standard.set(lang.rawValue, forKey: AppLanguage.storageKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: AppLanguage.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
            }
        }
        body()
    }

    func testPreferredLocaleFollowsTurkishAppLanguage() {
        withAppLanguage(.turkish) {
            XCTAssertEqual(MealSpeechRecognizer.preferredLocale.identifier, "tr-TR")
        }
    }

    func testPreferredLocaleFollowsEnglishAppLanguage() {
        withAppLanguage(.english) {
            XCTAssertEqual(MealSpeechRecognizer.preferredLocale.identifier, "en-US")
        }
    }

    func testRecognizerStartsIdleAndNotListening() {
        let recognizer = MealSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
        XCTAssertEqual(recognizer.state, .idle)
        XCTAssertFalse(recognizer.isListening)
        XCTAssertEqual(recognizer.transcript, "")
    }

    func testStopIsSafeWhenNotListening() {
        let recognizer = MealSpeechRecognizer(locale: Locale(identifier: "en-US"))
        recognizer.stop() // must be a no-op, never crash
        XCTAssertEqual(recognizer.state, .idle)
    }
}
