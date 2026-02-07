//
//  ResultView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/22/24.
//

import SwiftUI

struct CPTSummary: Identifiable {
    let id: Int
    let code: String
    let count: Int
    let total2020: Double
    let total2024: Double
}

struct ResultView: View {
    let totalRVUs2020: Double
    let totalRVUs2024: Double
    let cptSummaries: [CPTSummary]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Total RVUs")
                    .font(.largeTitle)
                    .padding(.top)

                VStack(spacing: 12) {
                    Text("2020 Schedule")
                        .font(.headline)
                    Text("\(totalRVUs2020, specifier: "%.2f")")
                        .font(.title)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)

                VStack(spacing: 12) {
                    Text("2024 Schedule")
                        .font(.headline)
                    Text("\(totalRVUs2024, specifier: "%.2f")")
                        .font(.title)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)

                VStack(spacing: 10) {
                    Text("CPT Summary")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Text("CPT")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("2020")
                            .frame(width: 90, alignment: .trailing)
                        Text("2024")
                            .frame(width: 90, alignment: .trailing)
                    }
                    .font(.subheadline.bold())

                    ForEach(cptSummaries) { summary in
                        HStack {
                            Text("\(summary.code) x\(summary.count)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(summary.total2020, specifier: "%.2f")")
                                .frame(width: 90, alignment: .trailing)
                            Text("\(summary.total2024, specifier: "%.2f")")
                                .frame(width: 90, alignment: .trailing)
                        }
                        .font(.subheadline)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            }
            .padding()
        }
        .navigationTitle("Results")
    }
}
//#Preview {
//    ResultView()
//}
