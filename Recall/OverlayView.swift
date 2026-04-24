import SwiftUI
import AppKit

struct OverlayView: View {
    let items: [HistoryItem]
    @Binding var selectedIndex: Int

    var body: some View {
        if items.isEmpty {
            EmptyStateView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipboardItemCard(item: item, isSelected: index == selectedIndex)
                                .id(item.id)
                                .onTapGesture { selectedIndex = index }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .padding(.top, 6)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selectedIndex) { newIndex in
                    guard newIndex < items.count else { return }
                    withAnimation { proxy.scrollTo(items[newIndex].id, anchor: .center) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.clear)
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "clipboard")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing copied yet")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

struct ClipboardItemCard: View {
    let item: HistoryItem
    let isSelected: Bool

    private static let cardWidth: CGFloat = 150
    private static let cardHeight: CGFloat = 150

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .shadow(color: isSelected ? .black.opacity(0.35) : .black.opacity(0.12),
                        radius: isSelected ? 10 : 4,
                        y: isSelected ? 4 : 2)

            if item.kind == .image, let path = item.imagePath {
                imageCardContent(path: path)
            } else {
                textCardContent
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.5)
        )
    }

    private var textCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: appIcon(for: item.sourceBundleId))
                .resizable()
                .frame(width: 16, height: 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 5)

            Text(item.text ?? "")
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(4)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Text(relativeTimestamp(item.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .padding(10)
    }

    private func imageCardContent(path: String) -> some View {
        VStack(spacing: 0) {
            Group {
                if let img = NSImage(contentsOfFile: path) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.2)
                        .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .clipped()

            HStack {
                Image(nsImage: appIcon(for: item.sourceBundleId))
                    .resizable()
                    .frame(width: 16, height: 16)
                Spacer()
                Text(relativeTimestamp(item.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func appIcon(for bundleId: String?) -> NSImage {
        if let bundleId,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60:     return "just now"
        case ..<3600:   return "\(seconds / 60)m ago"
        case ..<86400:  return "\(seconds / 3600)h ago"
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}
