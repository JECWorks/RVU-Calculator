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
    @Environment(\.colorScheme) private var colorScheme

    let totalRVUs2020: Double
    let totalRVUs2024: Double
    let cptSummaries: [CPTSummary]

    private var is2024Higher: Bool { totalRVUs2024 > totalRVUs2020 }
    private var is2020Higher: Bool { totalRVUs2020 > totalRVUs2024 }
    private var totalBlueCardTint: Color { colorScheme == .dark ? Color.blue.opacity(0.24) : Color.blue.opacity(0.12) }
    private var totalGreenCardTint: Color { colorScheme == .dark ? Color.green.opacity(0.24) : Color.green.opacity(0.12) }
    private var cptBlueChipBackground: Color { colorScheme == .dark ? Color.blue.opacity(0.30) : Color.blue.opacity(0.14) }
    private var cptGreenChipBackground: Color { colorScheme == .dark ? Color.green.opacity(0.30) : Color.green.opacity(0.14) }

    private var changeText: String {
        guard totalRVUs2020 > 0 else { return "N/A" }
        let pct = ((totalRVUs2024 - totalRVUs2020) / totalRVUs2020) * 100
        return String(format: "%+.1f%% vs 2020", pct)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Total RVUs")
                    .font(.title)
                    .fontWeight(.semibold)
                    .padding(.top, 4)

                HStack(spacing: 12) {
                    totalCard(
                        title: "2020 Schedule",
                        value: totalRVUs2020,
                        tint: totalBlueCardTint,
                        emphasized: is2020Higher,
                        badge: nil
                    )

                    totalCard(
                        title: "2024 Schedule",
                        value: totalRVUs2024,
                        tint: totalGreenCardTint,
                        emphasized: is2024Higher,
                        badge: changeText
                    )
                }

                VStack(spacing: 10) {
                    Text("CPT Summary")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Text("CPT")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("2020")
                            .frame(width: 96, alignment: .trailing)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(cptBlueChipBackground)
                            .cornerRadius(6)
                        Text("2024")
                            .frame(width: 96, alignment: .trailing)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(cptGreenChipBackground)
                            .cornerRadius(6)
                    }
                    .font(.subheadline.bold())
                    .padding(.horizontal, 6)

                    Divider()

                    if cptSummaries.isEmpty {
                        Text("No CPT entries with charges.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(Array(cptSummaries.enumerated()), id: \.element.id) { index, summary in
                            HStack {
                                Text("\(summary.code) x\(summary.count)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(summary.total2020, specifier: "%.2f")")
                                    .font(.body.monospacedDigit())
                                    .frame(width: 96, alignment: .trailing)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .background(cptBlueChipBackground)
                                    .cornerRadius(6)
                                Text("\(summary.total2024, specifier: "%.2f")")
                                    .font(.body.monospacedDigit())
                                    .frame(width: 96, alignment: .trailing)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .background(cptGreenChipBackground)
                                    .cornerRadius(6)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(index.isMultiple(of: 2) ? Color.white.opacity(0.45) : Color.clear)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(14)
                .background(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(.sRGB, white: 0.42, opacity: 1.0), Color(.sRGB, white: 0.20, opacity: 1.0)]
                            : [Color.white, Color(.sRGB, white: 0.94, opacity: 1.0)],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                )
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
            }
            .padding(16)
        }
        .navigationTitle("Results")
    }

    private func totalCard(title: String, value: Double, tint: Color, emphasized: Bool, badge: String?) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)

            Text("\(value, specifier: "%.2f")")
                .font(.title2.monospacedDigit())
                .fontWeight(.semibold)

            if let badge {
                Text(badge)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.7))
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(tint)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(emphasized ? Color.primary.opacity(0.35) : Color.gray.opacity(0.12), lineWidth: emphasized ? 2 : 1)
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}
//#Preview {
//    ResultView()
//}
