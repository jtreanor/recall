import SwiftUI
import AppKit

struct OverlayView: View {
    let items: [HistoryItem]
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardItemRow(item: item, isSelected: index == selectedIndex)
                            .id(item.id)
                            .onTapGesture { selectedIndex = index }
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedIndex) { newIndex in
                guard newIndex < items.count else { return }
                withAnimation { proxy.scrollTo(items[newIndex].id, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
    }
}

struct ClipboardItemRow: View {
    let item: HistoryItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if item.kind == .image, let path = item.imagePath {
                ImageThumbnail(path: path)
            } else {
                textPreview
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
        )
    }

    private var textPreview: some View {
        Text(item.text ?? "")
            .lineLimit(1)
            .truncationMode(.tail)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
    }
}

private struct ImageThumbnail: View {
    let path: String

    var body: some View {
        if let img = NSImage(contentsOfFile: path) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 200, maxHeight: 150)
                .cornerRadius(4)
        } else {
            Image(systemName: "photo")
                .frame(width: 40, height: 30)
                .foregroundStyle(.secondary)
        }
    }
}
