//
//  ScribeKitRootView.swift
//  ScribeKit
//

import SwiftUI

/// The main window's two screens: the meeting, and the meetings that are
/// already on disk.
///
/// The split is by what the user is doing rather than by what ScribeKit owns.
/// Both tabs read the same application-scoped ``MeetingRuntime``; neither owns
/// it, so moving between them starts, stops and duplicates nothing. A meeting
/// running on the Meeting tab keeps capturing, recognising and writing while
/// History is on screen.
struct ScribeKitRootView: View {

    /// The application's meeting owner, shared with the menu bar.
    let runtime: MeetingRuntime

    /// Creates the window's content.
    ///
    /// - Parameter runtime: The application's meeting owner.
    init(runtime: MeetingRuntime) {
        self.runtime = runtime
    }

    var body: some View {
        TabView {
            Tab("Meeting", systemImage: "waveform") {
                MeetingSetupView(runtime: runtime)
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                HistoryView(runtime: runtime)
            }
        }
        .frame(minWidth: 620, minHeight: 560)
    }
}

#Preview {
    ScribeKitRootView(runtime: MeetingRuntime())
}
