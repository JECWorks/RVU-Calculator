//
//  ContentView.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/20/24.
//

import SwiftUI

struct ContentView: View {
    @State private var year: Int?
    @State private var cptIndex: Int?
    @State private var numberOfPatients: String = ""
    @State private var totalRVUs: Double = 0.0
    @State private var sectionRVU: Double = 0.0
    
    let cptList = [
        (1, "99221", "Initial hospital care, level 1", 1.92, 1.63),
        (2, "99222", "Initial hospital care, level 2", 2.61, 2.60),
        (3, "99223", "Initial hospital care, level 3", 3.86, 3.50),
        (4, "99231", "Subsequent hospital care, level 1", 0.76, 1.00),
        (5, "99232", "Subsequent hospital care, level 2", 1.39, 1.59),
        (6, "99233", "Subsequent hospital care, level 3", 2.00, 2.40),
        (7, "99238", "Hospital discharge, ≤30 min", 1.28, 1.50),
        (8, "99239", "Hospital discharge, >30 min", 1.90, 2.15),
        (9, "99291", "Critical care, first 30-74 min", 4.50, 4.50),
        (10, "99292", "Critical care, each add. 30 min", 2.25, 2.25),
        (11, "99406", "Smoking cessation, 3-10 min", 0.24, 0.24),
        (12, "99407", "Smoking cessation, >10 min", 0.50, 0.50),
        (13, "99497", "Advance care planning, 30 min", 1.50, 1.50),
        (14, "99498", "Advance care planning, add. 30 min", 1.40, 1.40),
        (15, "99356", "Prolonged inpatient service, 1 hr", 2.93, 2.93),
        (16, "99357", "Prolonged inpatient service, add. 30 min", 1.45, 1.45)
    ]
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Select Year")
                    .font(.headline)
                Picker(selection: $year, label: Text("Year")) {
                    Text("2020").tag(1)
                    Text("2023").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                if let selectedYear = year {
                    Text("You chose \(selectedYear == 1 ? "2020" : "2023")")
                        .padding()
                    
                    Text("Select CPT Code")
                        .font(.headline)
                    
                    #if os(iOS)
                    Picker(selection: $cptIndex, label: Text("CPT Code")) {
                        ForEach(cptList, id: \.0) { item in
                            Text("\(item.1) - \(item.2)").tag(item.0 as Int?)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    .padding()
                    #else
                    Picker(selection: $cptIndex, label: Text("CPT Code")) {
                        ForEach(cptList, id: \.0) { item in
                            Text("\(item.1) - \(item.2)").tag(item.0 as Int?)
                        }
                    }
                    .padding()
                    #endif
                    
                    if let selectedCPTIndex = cptIndex {
                        let selectedCPT = cptList[selectedCPTIndex - 1]
                        let rvu = selectedYear == 1 ? selectedCPT.3 : selectedCPT.4
                        Text("The value of CPT code \(selectedCPT.1) is \(rvu)")
                            .padding()
                        
                        #if os(iOS)
                        TextField("Enter number of patients", text: $numberOfPatients)
                            .padding()
                            .keyboardType(.numberPad)
                        #else
                        TextField("Enter number of patients", text: $numberOfPatients)
                            .padding()
                        #endif
                        
                        Button(action: {
                            if let patients = Int(numberOfPatients) {
                                sectionRVU = rvu * Double(patients)
                                totalRVUs += sectionRVU
                                numberOfPatients = ""
                            }
                        }) {
                            Text("Calculate RVUs")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding()
                        
                        Text("You saw \(numberOfPatients) patients at CPT code \(selectedCPT.1), which equals \(sectionRVU) RVUs")
                            .padding()
                        
                        Text("Total RVUs for the day: \(totalRVUs)")
                            .padding()
                    }
                }
            }
            .navigationTitle("CPT RVU Calculator")
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
