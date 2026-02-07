//
//  CPTListView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/22/24.
//
import SwiftUI

struct CPTListView: View {
    @State private var chargeCounts: [Int: String] = [:]
    @State private var totalRVUs2020: Double = 0
    @State private var totalRVUs2024: Double = 0
    @State private var cptSummaries: [CPTSummary] = []
    @State private var navigateToResults = false

    var body: some View {
        VStack {
            List(cptCodes) { cpt in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cpt.code)
                            .font(.headline)
                        Text(cpt.description)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    TextField("0", text: binding(for: cpt))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.vertical, 4)
            }

            Button(action: calculateTotals) {
                Text("Calculate Total RVUs")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("CPT Charge Entry")
        .navigationDestination(isPresented: $navigateToResults) {
            ResultView(
                totalRVUs2020: totalRVUs2020,
                totalRVUs2024: totalRVUs2024,
                cptSummaries: cptSummaries
            )
        }
    }

    private func binding(for cpt: CPTCode) -> Binding<String> {
        Binding(
            get: { chargeCounts[cpt.id, default: ""] },
            set: { newValue in
                let digitsOnly = newValue.filter(\.isNumber)
                chargeCounts[cpt.id] = digitsOnly
            }
        )
    }

    private func calculateTotals() {
        cptSummaries = cptCodes.compactMap { cpt in
            let count = Int(chargeCounts[cpt.id] ?? "") ?? 0
            guard count > 0 else { return nil }

            return CPTSummary(
                id: cpt.id,
                code: cpt.code,
                count: count,
                total2020: Double(count) * cpt.rvu2020,
                total2024: Double(count) * cpt.rvu2024
            )
        }

        totalRVUs2020 = cptCodes.reduce(0) { result, cpt in
            let count = Int(chargeCounts[cpt.id] ?? "") ?? 0
            return result + (Double(count) * cpt.rvu2020)
        }

        totalRVUs2024 = cptCodes.reduce(0) { result, cpt in
            let count = Int(chargeCounts[cpt.id] ?? "") ?? 0
            return result + (Double(count) * cpt.rvu2024)
        }

        navigateToResults = true
    }
}

//#Preview {
//    CPTListView()
//}
