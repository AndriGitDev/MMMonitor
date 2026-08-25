import SwiftUI

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var fixedRange: ClosedRange<Double>?

    var body: some View {
        GeometryReader { geometry in
            let points = normalizedPoints(in: geometry.size)

            ZStack(alignment: .bottom) {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geometry.size.height))
                        for point in points {
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.28), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let maximumPointCount = max(2, Int(size.width.rounded(.up)))
        let plottedValues: [Double]
        if values.count > maximumPointCount {
            let stride = Double(values.count - 1) / Double(maximumPointCount - 1)
            plottedValues = (0..<maximumPointCount).map { index in
                values[min(values.count - 1, Int((Double(index) * stride).rounded()))]
            }
        } else {
            plottedValues = values
        }
        let lower = fixedRange?.lowerBound ?? 0
        let observedMaximum = plottedValues.max() ?? 1
        let upper = max(fixedRange?.upperBound ?? observedMaximum, lower + 0.000_001)

        return plottedValues.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(plottedValues.count - 1)
            let normalized = min(1, max(0, (value - lower) / (upper - lower)))
            let y = size.height * (1 - CGFloat(normalized))
            return CGPoint(x: x, y: y)
        }
    }
}
