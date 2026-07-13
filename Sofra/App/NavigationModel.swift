//
//  NavigationModel.swift
//  Sofra — app-wide flow state.
//
//  v2 structure: a persistent 3-tab home (Bugün · Geçmiş · Ayarlar) with the
//  scan task-flow (camera → analysis → result, or text-log → result) presented
//  as a full-screen cover over the tabs.
//
//  The scan-flow method names are unchanged from v1 so the camera/analysis/
//  result/text-log screens keep calling the same API — only their effect
//  changed (they now drive `scanFlow` instead of a single `screen`).
//

import SwiftUI
import Observation
import UIKit

// MARK: - Tabs

enum AppTab: Hashable {
    case today
    case history
    case settings
}

// MARK: - Scan flow (presented as a full-screen cover)

enum ScanFlow: Equatable {
    case camera
    case analyzing(imageData: Data, uiImage: UIImage)
    case result(uiImage: UIImage, items: [VisionItem], source: ScanSource, rawJSON: String)
    case textLog

    static func == (lhs: ScanFlow, rhs: ScanFlow) -> Bool {
        switch (lhs, rhs) {
        case (.camera, .camera): return true
        case (.textLog, .textLog): return true
        case (.analyzing(let ld, let lu), .analyzing(let rd, let ru)):
            return ld == rd && lu === ru
        case (.result(let li, let lv, let ls, let lj), .result(let ri, let rv, let rs, let rj)):
            return li === ri && lv.map(\.name) == rv.map(\.name) && ls == rs && lj == rj
        default: return false
        }
    }
}

@MainActor
@Observable
final class NavigationModel {

    /// Selected home tab. `.today` is the launch surface.
    var selectedTab: AppTab = .today

    /// The active scan flow, or nil when the user is on the tabbed home.
    var scanFlow: ScanFlow? = nil

    /// Whether to show the free-scan-limit screen (checked when entering a scan).
    var showFreeScanLimit: Bool = false

    /// Where the text-log screen was opened from — its close returns there.
    enum TextLogOrigin {
        case camera, daily
    }
    private(set) var textLogOrigin: TextLogOrigin = .camera

    /// Draft of the text-log input, kept so backing out of a result doesn't lose it.
    var textLogDraft: String = ""

    // MARK: - Scan-flow navigation (names preserved from v1)

    func goToCamera() {
        scanFlow = .camera
    }

    func startAnalysis(imageData: Data, uiImage: UIImage) {
        scanFlow = .analyzing(imageData: imageData, uiImage: uiImage)
    }

    func showResult(
        uiImage: UIImage,
        items: [VisionItem],
        source: ScanSource = .photo,
        rawJSON: String
    ) {
        scanFlow = .result(uiImage: uiImage, items: items, source: source, rawJSON: rawJSON)
    }

    /// Finish the scan flow and land back on the Bugün tab (used after logging
    /// and by the camera close button).
    func goToDaily() {
        scanFlow = nil
        selectedTab = .today
    }

    func goToTextLog(from origin: TextLogOrigin) {
        textLogOrigin = origin
        scanFlow = .textLog
    }

    /// Close the text-log screen. Opened from the camera → back to the camera;
    /// opened from the home → dismiss the whole flow back to the tabs.
    func closeTextLog() {
        switch textLogOrigin {
        case .camera: scanFlow = .camera
        case .daily:  scanFlow = nil
        }
    }

    /// Dismiss a result without logging. Photo scans return to the camera,
    /// text scans return to the text-log editor (the draft is preserved).
    func dismissResult(source: ScanSource) {
        switch source {
        case .text:  scanFlow = .textLog
        default:     scanFlow = .camera
        }
    }

    /// Dismiss any active scan flow back to the tabs.
    func dismissScanFlow() {
        scanFlow = nil
    }
}
