//
//  FeatureLabel.swift
//  LiveLoop
//
//  The label of each beta feature's main control, in the System Settings
//  style: a tinted icon, a title and one line saying what it does. Options
//  that only matter once a feature is on sit below it, lined up with the
//  title (`optionInset`).
//

import SwiftUI

struct FeatureLabel: View {

    /// Icon width plus spacing, so option rows line up with the title.
    static let optionInset: CGFloat = 30

    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            FeatureIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A white symbol on a small tinted rounded square, like System Settings.
struct FeatureIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// An inline warning with, when there is one, the button that fixes it.
struct InlineWarning: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
    }
}
