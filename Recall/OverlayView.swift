import SwiftUI
import AppKit

struct OverlayView: View {
    let items: [HistoryItem]
    let totalItemCount: Int
    @Binding var selectedIndex: Int
    @Binding var searchQuery: String
    @Binding var isSearchExpanded: Bool
    var selectionStyle: SelectionStyle = .borderNormal
    var onPaste: (() -> Void)?

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)
            content
        }
        .onChange(of: isSearchExpanded) { expanded in
            if expanded {
                DispatchQueue.main.async { searchFocused = true }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                    .opacity(isSearchExpanded ? 1 : 0)
            }
            .padding(.horizontal, 7)
            .frame(width: isSearchExpanded ? 210 : 25, height: 22, alignment: .leading)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(isSearchExpanded ? 0.07 : 0))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                    isSearchExpanded = true
                }
            }
            .padding(.leading, 10)

            Spacer()

            if !isSearchExpanded {
                Text(selectionStyle.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 12)
                    .transition(.opacity)
            }
        }
        .frame(height: 32)
    }

    @ViewBuilder
    private var content: some View {
        if totalItemCount == 0 {
            EmptyStateView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No results")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipboardItemCard(item: item, isSelected: index == selectedIndex, selectionStyle: selectionStyle)
                                .id(item.id)
                                .onTapGesture {
                                    selectedIndex = index
                                    onPaste?()
                                }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .padding(.top, 4)
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
    var selectionStyle: SelectionStyle = .borderNormal

    private static let cardWidth: CGFloat = 150
    private static let cardHeight: CGFloat = 150

    var body: some View {
        cardBody
            .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    private var cardBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(isSelected ? 0.35 : 0.12),
                        radius: isSelected ? 10 : 4,
                        y: isSelected ? 4 : 2)

            if item.isSensitive {
                sensitiveCardContent
            } else if item.kind == .image, let path = item.imagePath {
                imageCardContent(path: path)
            } else {
                textCardContent
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: borderWidth)
        )
    }

    // MARK: – Style helpers

    private var borderColor: Color {
        isSelected ? Color.accentColor.opacity(selectionStyle == .borderStrong ? 1.0 : 0.7) : .clear
    }

    private var borderWidth: CGFloat {
        selectionStyle == .borderStrong ? 2.0 : 1.5
    }

    private var sensitiveCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "lock.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 5)

            Text("••••••••")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Text(relativeTimestamp(item.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .padding(10)
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
