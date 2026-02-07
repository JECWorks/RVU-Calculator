//
//  ResultView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/22/24.
//

import SwiftUI

struct ResultView: View {
    let totalRVUs2020: Double
    let totalRVUs2024: Double

    var body: some View {
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

            Spacer()
        }
        .padding()
        .navigationTitle("Results")
    }
}
//#Preview {
//    ResultView()
//}
