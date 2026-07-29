import SwiftUI
import AppKit

@available(*, deprecated, message: "Use DraggableAppIcon instead")
struct AppIcon: View {
    let item: ApplicationItem
    var size: CGFloat = 64

    var body: some View {
        Image(nsImage: item.loadIcon(size: size))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            .compositingGroup()  // GPU: batch rendering
    }
}

@available(*, deprecated, message: "Use DraggableAppIcon instead")
struct AppIconButton: View {
    let item: ApplicationItem
    var size: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                AppIcon(item: item, size: size)
                Text(item.displayName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(4)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
struct AppIcon_Preview: PreviewProvider {
    static var previews: some View {
        AppIcon(item: ApplicationItem(bundleIdentifier: "com.novalaunch.sample",
                                      displayName: "Sample",
                                      name: "Sample",
                                      bundlePath: "/System/Applications/Messages.app"))
    }
}
#endif
