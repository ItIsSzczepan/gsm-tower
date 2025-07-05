//
//  ContentView.swift
//  GSMTowerWatch Watch App
//
//  Created by Jakub Szczepaniak on 01/07/2025.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var session = WatchSessionManager.shared
    @State private var showCompass = false
    @State private var receivedPoint: Point? = nil
    
    var body: some View {
        VStack {
            if let point = receivedPoint {
                Text("Otrzymano punkt!")
                    .font(.headline)
                Button("Otwórz kompas") {
                    showCompass = true
                }
                .sheet(isPresented: $showCompass) {
                    CompassView(point: point)
                }
            } else {
                Text("Oczekiwanie na punkt z iPhone'a...")
                    .font(.footnote)
            }
        }
        .onReceive(session.$receivedPoint) { point in
            if let point = point {
                receivedPoint = point
                showCompass = true
            }
        }
    }
}

#Preview {
    ContentView()
}
