import SwiftUI

struct PreviewTextSize: ViewModifier {
    func body(content: Content) -> some View {
        if CommandLine.arguments.contains("--large-type") { content.dynamicTypeSize(.accessibility2) }
        else { content }
    }
}

private struct NativePrimaryAction: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent).controlSize(.large).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
        }
    }
}

private struct AdaptiveNavigation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabViewStyle(.sidebarAdaptable).tabBarMinimizeBehavior(.onScrollDown)
        } else if #available(iOS 18.0, *) {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}

private struct NativeSecondaryAction: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass).controlSize(.large).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule)
        }
    }
}

extension View {
    func nativePrimaryAction() -> some View { modifier(NativePrimaryAction()) }
    func nativeSecondaryAction() -> some View { modifier(NativeSecondaryAction()) }
    func adaptiveNavigation() -> some View { modifier(AdaptiveNavigation()) }
}
