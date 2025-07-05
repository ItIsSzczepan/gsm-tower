//
//  ComapssView.swift
//  GSMTower
//
//  Created by Jakub Szczepaniak on 18/06/2025.
//

import CoreLocation
import SwiftUI

struct CompassView: View {
    let point: Point
    @StateObject private var viewModel = CompassViewModel()

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                // Obracane koło kompasu
                Circle()
                    .stroke(lineWidth: 4)
                    .foregroundColor(.gray)
                    .frame(width: 220, height: 220)

                // Kierunki świata obracane razem z kołem
                ForEach(0..<4) { i in
                    let directions = ["N", "E", "S", "W"]
                    let angle = .pi / 2 * Double(i) - .pi / 2
                    let x = 110 + 90 * cos(angle)
                    let y = 110 + 90 * sin(angle)
                    Text(directions[i])
                        .font(.headline)
                        .position(x: x, y: y)
                        .rotationEffect(.degrees(-viewModel.heading))
                }

                // Igła kompasu - obraca się względem heading, wskazuje kierunek do punktu względem urządzenia
                CompassNeedle(
                    angle: viewModel.bearingToPoint(
                        from: viewModel.userLocation,
                        to: CLLocationCoordinate2D(
                            latitude: point.latitude,
                            longitude: point.longitude
                        )
                    ),
                    heading: viewModel.heading
                )
            }
            .frame(width: 220, height: 220)

            #if os(iOS)
            details
            #endif
        }
        .onAppear {
            viewModel.startUpdating()
        }
        .onDisappear {
            viewModel.stopUpdating()
        }
    }
    
    private var details: some View {
        VStack {
            Text(
                "Kierunek do punktu: \(Int(viewModel.bearingToPoint(from: viewModel.userLocation, to: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))))°"
            )
            Text(
                "Twoje położenie: \(viewModel.userLocation.latitude), \(viewModel.userLocation.longitude)"
            )
            sendButton
        }
    }
    
    private var sendButton: some View{
        Button(action: {
            WatchSessionManager.shared.sendPointToWatch(point: point)
        }) {
            Label("Wyślij na Apple Watch", systemImage: "applewatch")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
    }
    
}

struct CompassNeedle: View {
    let angle: Double  // azymut do punktu
    let heading: Double  // aktualny heading urządzenia

    var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 6, height: 90)
            .offset(y: -45)
            .rotationEffect(.degrees(angle - heading))
    }
}
