//
//  ResultView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/22/24.
//

import SwiftUI

struct ResultView: View {
    let totalRVUs: Double
    
    var body: some View {
        VStack {
            Text("Total RVUs for the day:")
                .font(.headline)
                .padding()
            
            Text("\(totalRVUs, specifier: "%.2f")")
                .font(.largeTitle)
                .padding()
        }
        .navigationTitle("Results")
    }
}

#Preview {
    ResultView()
}
