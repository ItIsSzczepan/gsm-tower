//
//  PointDetailView.swift
//  GSMTower
//
//  Created by Jakub Szczepaniak on 03/06/2025.
//

import SwiftUI

struct PointDetailView: View {
    @StateObject private var viewModel: PointDetailViewModel
    
    
    
    init(point: Point) {
        _viewModel = StateObject(wrappedValue: PointDetailViewModel(point: point))
    }
    
    var body: some View {
        NavigationView {
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Nagłówek
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(viewModel.point.color())
                                .frame(width: 14, height: 14)
                            
                            Text("Stacja: \(viewModel.stationId)")
                                .font(.title2)
                                .bold()
                        }
                        
                        // Nazwa operatora (jeśli istnieje)
                        if let mainOperator = viewModel.mainOperator {
                            Text("Operator: \(mainOperator)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Miasto: \(viewModel.city)")
                        Text("Lokalizacja: \(viewModel.location)")
                        Text("ID: \(viewModel.stationId)")
                    }
                    
                    
                    Divider()
                    
                    // Pytania Tak/Nie
                    VStack(spacing: 12) {
                        QuestionView(
                            title: "Czy maszt istnieje?",
                            selection: $viewModel.existsAnswer
                        )
                        
                        QuestionView(
                            title: "Czy maszt działa?",
                            selection: $viewModel.workingAnswer
                        )
                    }
                    
                    Divider()
                    
                    // Kompas
                    NavigationLink(destination: CompassView(point: viewModel.point)) {
                        Label("Otwórz kompas", systemImage: "location.north.line")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    Divider()
                    
                    // Pozwolenia
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pozwolenia")
                            .font(.headline)
                        
                        ForEach(viewModel.uniquePermissions, id: \.self) { perm in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    // Technologia
                                    Text(perm.technology.uppercased())
                                        .font(.subheadline)
                                        .bold()
                                    
                                    // Operator
                                    Text(perm.operatorName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    // Decyzja i data
                                    Text("Decyzja: \(perm.decisionNumber)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    
                                }
                                
                                Spacer()
                                
                                Text("Ważne do: \(viewModel.formattedDate(perm.expiryDate))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    
                }
                .padding()
            }
            .navigationTitle("Szczegóły punktu")
            
        }
    }
    
}

struct QuestionView: View {
    let title: String
    @Binding var selection: Bool?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            HStack {
                Button(action: { selection = true }) {
                    Text("Tak")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selection == true ? Color.green : Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
                
                Button(action: { selection = false }) {
                    Text("Nie")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selection == false ? Color.red : Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
            }
        }
    }
}
