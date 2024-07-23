//
//  InputChargesView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/22/24.
//

import SwiftUI

struct InputChargesView: View {
    let selectedCPT: CPTCode
    let selectedYear: Int
    @State private var charges: String = ""
    @State private var totalRVUs: Double = 0
    @State private var navigateToResult = false
    
    var body: some View {
        VStack {
            Text("Enter charges for \(selectedCPT.code)")
                .font(.headline)
                .padding()
            
            TextField("Number of charges", text: $charges)
//                .keyboardType(.numberPad)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button(action: {
                if let chargesInt = Int(self.charges) {
                    let rvu = selectedYear == 2020 ? selectedCPT.rvu2020 : selectedCPT.rvu2024
                    self.totalRVUs += rvu * Double(chargesInt)
                }
                self.navigateToResult = true
            }) {
                Text("Add Charges")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Input Charges")
        .navigationDestination(isPresented: $navigateToResult) {
            ResultView(totalRVUs: totalRVUs)
        }
    }
}

//#Preview {
//    InputChargesView()
//}
