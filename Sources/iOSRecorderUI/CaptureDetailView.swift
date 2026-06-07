import SwiftUI
import DesignSystem
import iOSRecorder
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct CaptureDetailView: View {
    let summary: RecordSummary
    let controller: RecorderController
    @State private var record: Record?
    @State private var didReexport = false
    @Environment(\.colorPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let record {
                    if let shot = record.artifacts.first(where: { $0.kind == .screenshot }),
                       let image = Self.image(from: shot.data) {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12).stroke(palette.outlineVariant, lineWidth: 1)
                            }
                    }

                    ForEach(Array(record.artifacts.enumerated()), id: \.offset) { _, artifact in
                        if artifact.kind != .screenshot {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionHeader(artifactLabel(artifact.kind))
                                Card {
                                    artifactBody(artifact)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    Button {
                        Task { @MainActor in
                            await controller.reexport(record)
                            didReexport = true
                        }
                    } label: {
                        Label(didReexport ? "再送信しました" : "Mac に再送信", systemImage: "paperplane")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                    .disabled(didReexport)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(summary.metadata.screenName ?? "Capture")
        .task { record = await controller.record(for: summary.id) }
    }

    @ViewBuilder
    private func artifactBody(_ artifact: Artifact) -> some View {
        if artifact.mediaType == "application/json",
           let structured = StructuredValueView.parse(artifact.data) {
            StructuredValueView(value: structured)
        } else {
            ExpandableText(text: String(decoding: artifact.data, as: UTF8.self))
        }
    }

    private func artifactLabel(_ kind: ArtifactKind) -> String {
        switch kind.rawValue {
        case "network": return "通信"
        case "debug_timeline": return "タイムライン"
        case "metrics": return "メトリクス"
        case "state": return "状態"
        case "log": return "ログ"
        default: return kind.rawValue
        }
    }

    static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) { return Image(uiImage: uiImage) }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(data: data) { return Image(nsImage: nsImage) }
        #endif
        return nil
    }
}
