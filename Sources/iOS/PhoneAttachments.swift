import SwiftUI
import PhotosUI

struct PhoneAttachmentStrip: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(app.pendingImages) { image in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let preview = image.preview {
                                Image(platform: preview)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.white.opacity(0.12)
                            }
                        }
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Button { app.removePendingImage(image) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(.white))
                        }
                        .offset(x: 6, y: -6)
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

struct PhonePhotoButton: View {
    @EnvironmentObject var app: AppModel
    @State private var picked: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(selection: $picked, maxSelectionCount: 4, matching: .images) {
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: Phone.control, height: Phone.control)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                )
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for (index, item) in items.enumerated() {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    app.addPendingImage(
                        name: "photo-\(app.pendingImages.count + index + 1).jpg",
                        mediaType: mediaType(for: data),
                        data: data
                    )
                }
                picked = []
            }
        }
    }

    // The picker hands over whatever the library holds, and dsh needs the type
    // named correctly, so read it off the first bytes rather than the filename.
    private func mediaType(for data: Data) -> String {
        let head = [UInt8](data.prefix(4))
        if head.starts(with: [0x89, 0x50]) { return "image/png" }
        if head.starts(with: [0x47, 0x49]) { return "image/gif" }
        if head.starts(with: [0x52, 0x49]) { return "image/webp" }
        return "image/jpeg"
    }
}

struct OpenedImage: Identifiable {
    let id: String
    let image: PlatformImage
}

struct PhoneMediaCard: View {
    let image: PlatformImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(platform: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Phone.radiusCard, style: .continuous))
                .padding(Phone.margin)
            VStack {
                Spacer()
                HStack(spacing: 14) {
                    Button { UIPasteboard.general.image = image } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    Text("\(Int(image.size.width))×\(Int(image.size.height))")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Capsule().fill(.white.opacity(0.14)))
                .padding(.bottom, 28)
            }
        }
    }
}
