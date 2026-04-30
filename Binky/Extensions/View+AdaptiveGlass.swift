// View+AdaptiveGlass.swift
// Applies the macOS 26 liquid glass effect where supported, falls back to
// .ultraThinMaterial on macOS 14–25 so the app runs on Sonoma and later.

import SwiftUI

extension View {
    /// Applies `.glassEffect(in:)` on macOS 26+; falls back to
    /// `.background(.ultraThinMaterial, in:)` on earlier releases.
    @ViewBuilder
    func adaptiveGlass(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
