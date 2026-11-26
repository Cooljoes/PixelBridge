import SwiftUI
import SwiftData

struct TransferView: View {
    @Bindable var model: TransferViewModel
    @Query(sort: \TransferTask.created, order: .reverse) private var entries: [TransferTask]
    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("No transfers yet", systemImage: "arrow.down.circle", description: Text("Select an original in Gallery to save it here."))
            }
            if !model.notice.isEmpty { Text(model.notice) }
            ForEach(entries) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.filename).font(.headline)
                    Text(item.status.capitalized).foregroundStyle(.secondary)
                    if item.status == TransferState.downloading.rawValue {
                        ProgressView(value: Double(item.received), total: max(1, Double(item.expected)))
                        let rate = ByteCountFormatter.string(fromByteCount: Int64(model.link.transfers.bytesPerSecond), countStyle: .file)
                        Text("\(rate)/s · \(Int(model.link.transfers.eta ?? 0))s remaining").font(.caption)
                    }
                    if item.status == TransferState.saved.rawValue {
                        HStack {
                            ShareLink(item: model.link.transfers.storage.file(item)) { Label("Share", systemImage: "square.and.arrow.up") }
                            Spacer()
                            Button("Save to Photos") { Task { await model.export(item) } }
                        }.buttonStyle(.borderless)
                    } else if item.status != TransferState.downloading.rawValue {
                        if !item.detail.isEmpty { Text(item.detail).font(.caption) }
                        Text("\(item.received) of \(item.expected) bytes on disk").font(.caption)
                        Button("Retry from beginning") { model.retry(item) }.disabled(model.link.state != .ready)
                    }
                }.padding(.vertical, 4)
            }
        }.navigationTitle("Transfers")
    }
}
