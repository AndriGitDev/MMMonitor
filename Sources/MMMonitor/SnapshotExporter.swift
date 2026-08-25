import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum SnapshotExporter {
    private struct Report: Encodable {
        let application: String
        let version: String
        let platform: String
        let snapshot: SystemSnapshot
    }

    static func copy(_ snapshot: SystemSnapshot) throws {
        let data = try encoded(snapshot)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ExportError.couldNotEncodeText
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func save(_ snapshot: SystemSnapshot) throws {
        let panel = NSSavePanel()
        panel.title = "Save MMMonitor Snapshot"
        panel.nameFieldStringValue = "MMMonitor-Snapshot.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try encoded(snapshot).write(to: url, options: .atomic)
    }

    private static func encoded(_ snapshot: SystemSnapshot) throws -> Data {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "development"
        let report = Report(
            application: "MMMonitor",
            version: version,
            platform: "macOS arm64",
            snapshot: snapshot
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    private enum ExportError: LocalizedError {
        case couldNotEncodeText

        var errorDescription: String? {
            "The snapshot could not be converted to text."
        }
    }
}
