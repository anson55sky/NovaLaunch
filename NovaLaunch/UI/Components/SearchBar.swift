import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "搜索应用…"
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.35))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ColorTheme.glassThin)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            isFocused = true
        }
    }
}

#if DEBUG
struct SearchBar_Preview: PreviewProvider {
    static var previews: some View {
        @FocusState var isFocused: Bool
        return SearchBar(text: .constant(""), isFocused: $isFocused)
    }
}
#endif
