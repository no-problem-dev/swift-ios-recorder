import SwiftUI
import DesignSystem
import iOSRecorderNetwork

struct NetworkListView: View {
    @Bindable var store: NetworkLogStore
    @State private var query = ""
    @Environment(\.colorPalette) private var palette

    private var filtered: [NetworkLog] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.logs }
        return store.logs.filter { log in
            log.url.lowercased().contains(q)
                || log.method.lowercased().contains(q)
                || log.host.lowercased().contains(q)
                || (log.statusCode.map { "\($0)" } ?? "").contains(q)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filtered) { log in
                    NavigationLink {
                        NetworkDetailView(log: log)
                    } label: {
                        NetworkRow(log: log)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle("Network")
        .searchable(text: $query, prompt: "URL・メソッド・ステータスで検索")
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "通信なし" : "一致なし",
                    systemImage: query.isEmpty ? "network.slash" : "magnifyingglass",
                    description: Text(query.isEmpty ? "アプリを操作すると通信が流れます" : "「\(query)」に一致する通信はありません")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) { store.clear() } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.logs.isEmpty)
                .tint(palette.error)
            }
        }
    }
}

struct NetworkRow: View {
    let log: NetworkLog
    @Environment(\.colorPalette) private var palette

    var body: some View {
        Card(elevation: .level1) {
            HStack(spacing: 10) {
                Circle().fill(statusColor).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(log.method).typography(.labelMedium).foregroundStyle(palette.onSurfaceVariant)
                        Text(log.path).typography(.bodyMedium).foregroundStyle(palette.onSurface).lineLimit(1)
                    }
                    Text(log.host).typography(.labelSmall).foregroundStyle(palette.outline).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(statusText).typography(.labelMedium).monospacedDigit().foregroundStyle(statusColor)
                    Text("\(Int(log.duration * 1000))ms").typography(.labelSmall).foregroundStyle(palette.outline)
                }
            }
        }
    }

    private var statusText: String {
        if log.errorMessage != nil { return "ERR" }
        if let code = log.statusCode { return "\(code)" }
        return "—"
    }

    private var statusColor: Color {
        if log.errorMessage != nil { return palette.outline }
        guard let code = log.statusCode else { return palette.onSurfaceVariant }
        switch code {
        case 200..<300: return palette.success
        case 300..<400: return palette.warning
        default: return palette.error
        }
    }
}

struct NetworkDetailView: View {
    let log: NetworkLog
    @Environment(\.colorPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("リクエスト") {
                    field("Method", log.method)
                    field("URL", log.url)
                    headers(log.requestHeaders)
                    bodyField(log.requestBody)
                }
                section("レスポンス") {
                    field("Status", log.statusCode.map(String.init) ?? log.errorMessage ?? "—")
                    field("Duration", "\(Int(log.duration * 1000)) ms")
                    headers(log.responseHeaders)
                    bodyField(log.responseBody)
                }
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(log.path)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            Card {
                VStack(alignment: .leading, spacing: 10) { content() }
            }
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).typography(.labelSmall).foregroundStyle(palette.onSurfaceVariant)
            Text(value).font(.footnote.monospaced()).foregroundStyle(palette.onSurface).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func headers(_ headers: [String: String]) -> some View {
        if !headers.isEmpty {
            let text = headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            field("Headers", text)
        }
    }

    @ViewBuilder
    private func bodyField(_ body: String?) -> some View {
        if let body, !body.isEmpty {
            field("Body", body)
        }
    }
}
