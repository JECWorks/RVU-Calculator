//
//  CPTListView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/22/24.
//
import SwiftUI

struct CPTListView: View {
    let selectedYear: Int
    @State private var selectedCPT: CPTCode? = nil
    
    var body: some View {
        List(cptCodes) { cpt in
            NavigationLink(destination: InputChargesView(selectedCPT: cpt, selectedYear: selectedYear)) {
                VStack(alignment: .leading) {
                    Text(cpt.code)
                    Text(cpt.description)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle("Select CPT Code")
    }
}

#Preview {
    CPTListView()
}
