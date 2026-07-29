import SwiftUI

@available(*, deprecated, message: "Use .glassCard() View modifier instead")
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .glassCard(cornerRadius: cornerRadius)
    }
}

#if DEBUG
struct GlassCard_Preview: PreviewProvider {
    static var previews: some View {
        GlassCard {
            Text("Glass Card")
                .padding()
        }
        .padding()
    }
}
#endif
