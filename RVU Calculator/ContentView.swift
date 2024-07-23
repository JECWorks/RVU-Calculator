//
//  ContentView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/20/24.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedYear: Int? = nil
    @State private var navigateToCPTList = false
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("RVU Calculator")
                    .font(.largeTitle)
                    .padding()
                
                Text("Select RVU Schedule Year")
                    .font(.headline)
                    .padding()
                
                HStack {
                    Button(action: {
                        self.selectedYear = 2020
                        self.navigateToCPTList = true
                    }) {
                        Text("2020")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    Button(action: {
                        self.selectedYear = 2024
                        self.navigateToCPTList = true
                    }) {
                        Text("2024")
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationDestination(isPresented: $navigateToCPTList) {
                if let selectedYear = selectedYear {
                    CPTListView(selectedYear: selectedYear)
                }
            }
        }
    }
}
    
#Preview {
    ContentView()
}
