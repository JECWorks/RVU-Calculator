//
//  RVU_CalculatorApp.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/20/24.
//

import SwiftUI
import SwiftData

@main
struct RVU_CalculatorApp: App {

    init() {
        #if os(macOS)
        // Disabling state restoration on macOS
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 400, minHeight: 600)
        }
        .modelContainer(for: [DayRecord.self])
        #if os(macOS)
        .commands {
            CommandMenu("Tools") {
                Button("Reset") {
                    // Add reset functionality if needed
                }
                .keyboardShortcut("R", modifiers: .command)
            }
        }
        #endif
    }
}
