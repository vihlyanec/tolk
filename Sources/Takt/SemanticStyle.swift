import SwiftUI
import TaktCore

/// Shared meanings across input, list rows and inspector; text/icons also identify each role.
enum SemanticTint {
    /// Upgrade the six original muted presets without rewriting stored user colors.
    static func vibrantHex(_ hex: String) -> String {
        let value = hex.replacingOccurrences(of: "#", with: "").uppercased()
        return ["598BFF":"4F8CFF", "5BC9A2":"28D9AD", "AD94E8":"B58AFF", "E6A467":"FFAD40", "ED8098":"FF66A0", "66BDCB":"35CCE8"][value] ?? value
    }
    static func capsuleOpacity(dark: Bool) -> Double { dark ? 0.20 : 0.12 }
    static func priority(_ value: Int, dark: Bool) -> NSColor {
        color(hex: value == 1 ? (dark ? "FF5E68" : "C52135") : value == 2 ? (dark ? "FFAD32" : "995900") : value == 3 ? (dark ? "5596FF" : "235DCF") : (dark ? "ACACB2" : "595960"), dark: dark)
    }
    static func color(hex: String, dark: Bool) -> NSColor {
        let raw = UInt64(vibrantHex(hex), radix: 16) ?? 0x598BFF
        let rgb = [Double((raw >> 16) & 255)/255, Double((raw >> 8) & 255)/255, Double(raw & 255)/255]
        // Preserve the chosen hue, adjust only enough to keep colored small text readable.
        let surface = dark ? 0.13 : 0.95
        let opacity = capsuleOpacity(dark: dark)
        let background = rgb.map { $0 * opacity + surface * (1 - opacity) }
        func luminance(_ c: [Double]) -> Double {
            let v = c.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return v[0]*0.2126 + v[1]*0.7152 + v[2]*0.0722
        }
        var foreground = rgb
        for step in 0...20 {
            let a = luminance(foreground), b = luminance(background)
            if (max(a,b)+0.05)/(min(a,b)+0.05) >= 5.5 { break }
            let mix = Double(step+1)/21
            foreground = rgb.map { $0*(1-mix) + (dark ? 1 : 0)*mix }
        }
        return NSColor(srgbRed: foreground[0], green: foreground[1], blue: foreground[2], alpha: 1)
    }
    static func token(_ token: QuickToken, projects: [Project], tags: [Tag], dark: Bool) -> NSColor {
        switch token.kind {
        case .tag:
            let name = String(token.value.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return color(hex: tags.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }?.color ?? "AD94E8", dark: dark)
        case .project:
            let name = String(token.value.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return color(hex: projects.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }?.color ?? "AD94E8", dark: dark)
        case .priority:
            let value = token.value.hasPrefix("!") ? Int(token.value.dropFirst()) ?? 0 : token.value.lowercased().hasPrefix("средний") ? 2 : token.value.lowercased().hasPrefix("низкий") ? 3 : 1
            return priority(value, dark: dark)
        case .date: return color(hex: dark ? "5BD6A2" : "16744B", dark: dark)
        case .time: return color(hex: dark ? "84ACFF" : "2354B7", dark: dark)
        case .duration: return color(hex: dark ? "68D1D8" : "176E76", dark: dark)
        }
    }
}

struct TagCapsule: View {
    let tag: Tag
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text("#" + tag.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            .foregroundStyle(Color(nsColor: SemanticTint.color(hex: tag.color, dark: scheme == .dark)))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(hex: tag.color).opacity(SemanticTint.capsuleOpacity(dark: scheme == .dark)), in: Capsule())
            .help("Тег: " + tag.name)
    }
}

struct PriorityCapsule: View {
    let priority: Int
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let tint = Color(nsColor: SemanticTint.priority(priority, dark: scheme == .dark))
        Label(AppState.priorityTitle(priority), systemImage: "flag.fill")
            .font(.system(size: 10, weight: .medium)).foregroundStyle(tint).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 4).background(tint.opacity(scheme == .dark ? 0.18 : 0.10), in: Capsule())
            .help("Приоритет: " + AppState.priorityTitle(priority))
    }
}

/// Wrap all available metadata instead of dropping tags after the first two.
struct MetadataFlow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 600, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in layout.points.enumerated() { subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(width: min(subviews[index].sizeThatFits(.unspecified).width, bounds.width), height: nil)) }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = max(1, width)
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, points: [CGPoint] = []
        for view in subviews {
            let natural = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(natural.width, width), height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}

struct ProjectTagColor: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }
}
enum ProjectTagPalette {
    static func nextColor(in snapshot: Snapshot) -> String {
        let used = Set((snapshot.projects.map(\.color) + snapshot.tags.map(\.color)).map(SemanticTint.vibrantHex))
        if let free = choices.filter({ !used.contains($0.hex) }).randomElement() { return free.hex }
        // When the presets are exhausted, keep the new color bright and unique.
        while true {
            let color = NSColor(srgbRed: Double.random(in: 0.2...1), green: Double.random(in: 0.2...1), blue: Double.random(in: 0.2...1), alpha: 1)
            guard max(color.redComponent, color.greenComponent, color.blueComponent) > 0.8,
                  max(color.redComponent, color.greenComponent, color.blueComponent) - min(color.redComponent, color.greenComponent, color.blueComponent) > 0.4 else { continue }
            let hex = String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
            if !used.contains(SemanticTint.vibrantHex(hex)) { return hex }
        }
    }

    static let choices: [ProjectTagColor] = [
        .init(name: "Синий", hex: "4F8CFF"), .init(name: "Индиго", hex: "7367FF"),
        .init(name: "Фиолетовый", hex: "B58AFF"), .init(name: "Пурпурный", hex: "C767F5"),
        .init(name: "Фуксия", hex: "EC5BD9"), .init(name: "Розовый", hex: "FF66A0"),
        .init(name: "Коралловый", hex: "FF6E78"), .init(name: "Красный", hex: "FF514D"),
        .init(name: "Оранжевый", hex: "FF9740"), .init(name: "Янтарный", hex: "FFAD40"),
        .init(name: "Жёлтый", hex: "E8D244"), .init(name: "Лаймовый", hex: "A7DE3B"),
        .init(name: "Зелёный", hex: "45D578"), .init(name: "Мятный", hex: "28D9AD"),
        .init(name: "Бирюзовый", hex: "26CFC0"), .init(name: "Голубой", hex: "35CCE8"),
        .init(name: "Небесный", hex: "58BFFF"), .init(name: "Серо-синий", hex: "94A9CD")
    ]
}
