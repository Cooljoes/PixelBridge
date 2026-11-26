import SwiftUI

struct GalleryView: View {
    @Bindable var model: GalleryViewModel
    var body: some View {
        Group {
            if let session = model.link.session {
                List {
                    if session.listingTruncated { Text("Showing media from the first 200 object handles.").font(.footnote) }
                    ForEach(model.files) { file in
                        NavigationLink { MediaDetail(file: file, model: model) } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.name)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "photo") }
                        }
                    }
                    if model.files.isEmpty { Text("No matching files on this card.") }
                }
                .searchable(text: $model.search)
            } else {
                ContentUnavailableView("Connect a camera", systemImage: "camera", description: Text("Open a camera from the Camera tab to browse its card."))
            }
        }.navigationTitle("Gallery")
    }
}

private struct MediaDetail: View {
    let file: MediaFile
    let model: GalleryViewModel
    var body: some View {
        List {
            Section {
                if model.link.previewFileID == file.id, let data = model.link.thumbnail, let image = GalleryViewModel.image(data) {
                    Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Camera thumbnail")
                }
                Button("Load thumbnail") { model.link.preview(file) }
                    .disabled(model.link.state != .ready || model.link.readingThumbnail)
            }
            Section("Original") {
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                if !file.captured.isEmpty { LabeledContent("Camera timestamp", value: file.captured) }
                Button("Download original") { model.link.download(file) }.disabled(model.link.state != .ready || model.link.readingThumbnail)
                if !model.link.message.isEmpty { Text(model.link.message).font(.footnote) }
            }
        }.navigationTitle(file.name).navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.link.thumbnail = nil }
    }
}
