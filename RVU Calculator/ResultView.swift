//
//  ResultView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/22/24.
//

import SwiftUI

struct ResultView: View {
    @Binding var totalRVUs: Double
    let selectedCPTTotalRVUs: Double
    let selectedYear: Int
    
    var body: some View {
        VStack {
            Text("Total RVUs for the day:")
                .font(.headline)
                .padding()
            
            Text("\(totalRVUs, specifier: "%.2f")")
                .font(.largeTitle)
                .padding()
            
            Text("Total RVUs for the selected CPT:")
                .font(.headline)
                .padding(.top)
            
            Text("\(selectedCPTTotalRVUs, specifier: "%.2f")")
                .font(.title)
                .padding(.bottom)
            
            NavigationLink(destination: CPTListView(selectedYear: selectedYear, totalRVUs: $totalRVUs)) {
                Text("Add Another CPT Code")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
            
            NavigationLink(destination: ContentView()) {
                Text("Start Over")
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Results")
    }
}
//#Preview {
//    ResultView()
//}
