import AppKit
import SwiftUI

@MainActor
enum AppBrand {
    static let name = "MMMonitor"
    static let tagline = "Apple Silicon performance at a glance."
    static let attribution = "A free community project by Kastro"
    static let compactAttribution = "by Kastro · Free & open source"
    static let credits = "\(attribution)\n\(tagline)\n\nLocal, lightweight, and open source.\nFree to use, share, and modify under the MIT License."

    // Bundled releases use the same artwork as Finder. SwiftPM development
    // launches have no bundled icon, so retain a native symbol as a fallback.
    static let icon: NSImage? = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }
}

struct AppBrandIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = AppBrand.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: size * 0.75, weight: .medium))
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
