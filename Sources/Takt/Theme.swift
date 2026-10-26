import SwiftUI
import TaktCore

// The SDK also exports an @ViewState macro that requires an Xcode-only plugin.
// This alias selects the stable property wrapper for Command Line Tools builds.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
    static let accent = Color(hex: "598BFF")
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let line = Color.primary.opacity(0.10)
}
struct BrandMark: View {
    private var image: NSImage? { Bundle.main.url(forResource: "BrandIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:)) }
    var body: some View {
        if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFit().accessibilityLabel("Толк") }
        else { Image(systemName: "checkmark.square.fill").resizable().scaledToFit().foregroundStyle(Palette.accent).padding(5).accessibilityLabel("Толк") }
    }
}
extension Color {
    init(hex: String) {
        let raw = UInt64(SemanticTint.vibrantHex(hex), radix: 16) ?? 0x4F8CFF
        self.init(red: Double((raw >> 16) & 255) / 255, green: Double((raw >> 8) & 255) / 255, blue: Double(raw & 255) / 255)
    }
}
struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(tint).frame(width: 30, height: 30).contentShape(Rectangle()) }
            .buttonStyle(.plain).focusEffectDisabled().help(help).accessibilityLabel(help)
    }
}
struct CompleteButton: View {
    let item: Item
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(item.priority == 0 ? Color.secondary : Color(nsColor: SemanticTint.priority(item.priority, dark: scheme == .dark)))
                .frame(width: 23, height: 23).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(item.deleted).help(item.completed ? "Вернуть в работу" : "Выполнить задачу")
            .accessibilityLabel(item.completed ? "Вернуть в работу: \(item.title)" : "Выполнить: \(item.title)")
    }
}
struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 310)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct Metadata: View {
    let state: AppState
    let item: Item
    var body: some View {
        MetadataFlow {
            HStack(spacing: 4) {
                Circle().fill(Color(hex: state.color(item))).frame(width: 6, height: 6)
                Text(state.projectName(item.projectID))
            }.foregroundStyle(.secondary)
            if item.section != "Без раздела" { Label(item.section, systemImage: "rectangle.split.3x1").foregroundStyle(.secondary) }
            if item.priority != 0 { PriorityCapsule(priority: item.priority) }
            ForEach(item.tagIDs, id: \.self) { id in
                if let tag = state.data.tags.first(where: { $0.id == id }) { TagCapsule(tag: tag) }
            }
        }.font(.system(size: 11)).lineLimit(1)
    }
}
