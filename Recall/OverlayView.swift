import SwiftUI
import AppKit

struct OverlayView: View {
    let items: [HistoryItem]
    let totalItemCount: Int
    @Binding var selectedIndex: Int
    @Binding var searchQuery: String
    @Binding var isSearchExpanded: Bool
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
                    LazyHStack(spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipboardItemCard(item: item, isSelected: index == selectedIndex)
                                .id(item.id)
                                .onTapGesture {
                                    selectedIndex = index
                                    onPaste?()
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .padding(.top, 10)
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

// MARK: - Tint cache (shared across all card instances)
private enum AppTintCache {
    static var colors: [String: Color] = [:]
}

struct ClipboardItemCard: View {
    let item: HistoryItem
    let isSelected: Bool

    private static let cardWidth: CGFloat = 180
    private static let cardHeight: CGFloat = 200
    private static let cornerRadius: CGFloat = 14

    private var isCodeItem: Bool {
        item.kind == .text && looksLikeCode(item.text)
    }

    private var typeLabel: String {
        if item.isSensitive { return "Password" }
        switch item.kind {
        case .text: return isCodeItem ? "Code" : "Text"
        case .image: return "Image"
        }
    }

    var body: some View {
        ZStack {
            cardBackground
            if item.isSensitive {
                sensitiveCardContent
            } else if item.kind == .image, let path = item.imagePath {
                imageCardContent(path: path)
            } else {
                textCardContent
            }
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        // Image pill lives outside clipShape so it is never clipped by the card corners
        .overlay(alignment: .topLeading) {
            if item.kind == .image {
                imagePill
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .stroke(isSelected ? Color.accentColor.opacity(0.85) : Color.clear, lineWidth: 1.75)
        )
        .shadow(
            color: isSelected ? .black.opacity(0.3) : .black.opacity(0.12),
            radius: isSelected ? 12 : 5,
            y: isSelected ? 5 : 2
        )
    }

    private var imagePill: some View {
        HStack(spacing: 5) {
            Image(nsImage: appIcon(for: item.sourceBundleId))
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
            Text(relativeTimestamp(item.createdAt))
                .font(.system(size: 11, weight: .medium))
        }
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.leading, 10)
        .padding(.top, 10)
    }

    // MARK: - Background

    @ViewBuilder
    private var cardBackground: some View {
        if isCodeItem {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
        } else {
            // Frosted glass base with subtle app-derived color tint on top
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(.thinMaterial)
            if let tint = resolvedTint {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(tint.opacity(0.35))
            }
        }
    }

    // Extracts or returns cached dominant color for the source app icon.
    private var resolvedTint: Color? {
        guard let bundleId = item.sourceBundleId else { return nil }
        if let cached = AppTintCache.colors[bundleId] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let color = dominantColor(from: icon)
        AppTintCache.colors[bundleId] = color
        return color
    }

    // Samples the icon at 12×12, averages opaque pixels, desaturates, and lightens.
    private func dominantColor(from image: NSImage) -> Color {
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(
                  data: &pixels, width: side, height: side,
                  bitsPerComponent: 8, bytesPerRow: side * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return .gray }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, n: CGFloat = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = CGFloat(pixels[i + 3]) / 255
            guard a > 0.5 else { continue }
            // Un-premultiply
            r += (CGFloat(pixels[i])     / 255) / a
            g += (CGFloat(pixels[i + 1]) / 255) / a
            b += (CGFloat(pixels[i + 2]) / 255) / a
            n += 1
        }
        guard n > 0 else { return .gray }
        r /= n; g /= n; b /= n

        // Desaturate moderately, keeping most of the hue
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        r = lum + (r - lum) * 0.7
        g = lum + (g - lum) * 0.7
        b = lum + (b - lum) * 0.7

        // Lighten toward white (less aggressive so color stays visible)
        r = r + (1 - r) * 0.3
        g = g + (1 - g) * 0.3
        b = b + (1 - b) * 0.3

        return Color(red: r, green: g, blue: b)
    }

    // MARK: - Card header row (text / sensitive cards)

    private func cardHeader(foregroundIsDark: Bool) -> some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 5) {
                Text(typeLabel)
                    .font(.system(size: 11, weight: .semibold))
                Text(relativeTimestamp(item.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(foregroundIsDark ? .white.opacity(0.45) : Color(nsColor: .tertiaryLabelColor))
            }
            .foregroundStyle(foregroundIsDark ? .white.opacity(0.7) : Color(nsColor: .secondaryLabelColor))

            Spacer()

            Image(nsImage: appIcon(for: item.sourceBundleId))
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
        }
    }

    // MARK: - Content variants

    private var textCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(foregroundIsDark: isCodeItem)
                .padding(.bottom, 7)

            Text(item.text ?? "")
                .font(isCodeItem
                      ? .system(size: 12, design: .monospaced)
                      : .system(size: 14))
                .foregroundStyle(isCodeItem ? Color.white.opacity(0.88) : Color(nsColor: .labelColor))
                .lineLimit(isCodeItem ? 8 : 6)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
    }

    private var sensitiveCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 5) {
                    Text("Password")
                        .font(.system(size: 11, weight: .semibold))
                    Text(relativeTimestamp(item.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 7)

            Text("••••••••")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
    }

    private func imageCardContent(path: String) -> some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: - Helpers

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
        case ..<60:     return "now"
        case ..<3600:   return "\(seconds / 60)m"
        case ..<86400:  return "\(seconds / 3600)h"
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    private func looksLikeCode(_ text: String?) -> Bool {
        guard let text, text.count > 30 else { return false }
        var score = 0
        let keywords = ["func ", "var ", "let ", "const ", "def ", "class ", "import ",
                        "struct ", "enum ", "#include", "return ", "->", "=>", ":=", "fn "]
        for kw in keywords where text.contains(kw) { score += 1 }
        if text.contains("{") && text.contains("}") { score += 1 }
        let lines = text.components(separatedBy: "\n")
        let indented = lines.dropFirst().filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }
        if lines.count > 2 && indented.count >= 2 { score += 1 }
        return score >= 2
    }
}
