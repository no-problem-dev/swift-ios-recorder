import SwiftUI
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let record {
                    if let shot = record.artifacts.first(where: { $0.kind == .screenshot }),
                       let image = Self.image(from: shot.data) {
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    ForEach(Array(record.artifacts.enumerated()), id: \.offset) { _, artifact in
                        if artifact.kind != .screenshot {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(artifact.kind.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(decoding: artifact.data, as: UTF8.self))
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(didReexport)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .navigationTitle(summary.metadata.screenName ?? "Capture")
        .task { record = await controller.record(for: summary.id) }
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
