import SwiftUI

/// The BetterYears Age bird, the team's logo (asset `BrandMark`, from the brand PNG in `docs/brand/`).
/// Drawn in the Dusk palette already, so it sits on glass as is: never tint or recolor it.
struct BrandMark: View {
    /// Height in points; the width follows the drawing.
    var size: CGFloat = 96

    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(height: size)
            .accessibilityLabel("BetterYears Age")
    }
}
