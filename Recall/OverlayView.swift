import SwiftUI
import AppKit

struct OverlayView: View {
    let items: [HistoryItem]
    @Binding var selectedIndex: Int

    var body: some View {
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
                .padding(.vertical, 14)
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

struct ClipboardItemCard: View {
    let item: HistoryItem
    let isSelected: Bool

    private static let cardWidth: CGFloat = 120
    private static let cardHeight: CGFloat = 140

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
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
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.5)
        )
    }

    private var textCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 5)

            Text(item.text ?? "")
                .font(.system(size: 11))
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
                Image(systemName: "photo")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
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
