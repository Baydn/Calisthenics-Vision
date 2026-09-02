//
//  Calisthenics_VisionApp.swift
//  Calisthenics Vision
//
//  Created by Baydon Galloway on 8/31/26.
//

import SwiftUI

@main
struct Calisthenics_VisionApp: App {
    @State private var entitlements = Entitlements()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(entitlements)
        }
    }
}
