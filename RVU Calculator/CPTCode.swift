//
//  CPTCode.swift
//  RVU Calculator
//
//  Created by Jason Cox on 7/22/24.
//

import SwiftUI

struct CPTCode: Identifiable {
    let id: Int
    let code: String
    let description: String
    let rvu2020: Double
    let rvu2024: Double
}

let cptCodes = [
    CPTCode(id: 1, code: "99221", description: "Initial hospital care, level 1", rvu2020: 1.92, rvu2024: 1.63),
    CPTCode(id: 2, code: "99222", description: "Initial hospital care, level 2", rvu2020: 2.61, rvu2024: 2.60),
    CPTCode(id: 3, code: "99223", description: "Initial hospital care, level 3", rvu2020: 3.86, rvu2024: 3.50),
    CPTCode(id: 4, code: "99231", description: "Subsequent hospital care, level 1", rvu2020: 0.76, rvu2024: 1.00),
    CPTCode(id: 5, code: "99232", description: "Subsequent hospital care, level 2", rvu2020: 1.39, rvu2024: 1.59),
    CPTCode(id: 6, code: "99233", description: "Subsequent hospital care, level 3", rvu2020: 2.00, rvu2024: 2.40),
    CPTCode(id: 7, code: "99238", description: "Hospital discharge ≤30 min", rvu2020: 1.28, rvu2024: 1.50),
    CPTCode(id: 8, code: "99239", description: "Hospital discharge, >30 min", rvu2020: 1.90, rvu2024: 2.15),
    CPTCode(id: 9, code: "99291", description: "Critical care, first 30-74 min", rvu2020: 4.50, rvu2024: 4.50),
    CPTCode(id: 10, code: "99292", description: "Critical care, each add. 30 min", rvu2020: 2.25, rvu2024: 2.25),
    CPTCode(id: 11, code: "99406", description: "Smoking cessation, 3-10 min", rvu2020: 0.24, rvu2024: 0.24),
    CPTCode(id: 12, code: "99407", description: "Smoking cessation, >10 min", rvu2020: 0.50, rvu2024: 0.50),
    CPTCode(id: 13, code: "99497", description: "Advance care planning, 30 min", rvu2020: 3.86, rvu2024: 3.50),
    CPTCode(id: 14, code: "99498", description: "Advance care planning, add. 30 min", rvu2020: 1.40, rvu2024: 1.40),
    CPTCode(id: 15, code: "99356", description: "Prolonged inpatient service, 1 hr", rvu2020: 2.93, rvu2024: 2.93),
    CPTCode(id: 16, code: "99357", description: "Prolonged inpatient service, add. 30 min", rvu2020: 1.45, rvu2024: 1.45)
]

