import SwiftUI
import UIKit

/// Opens the nearest enclosing `SidebarDrawer`.
struct OpenSidebarAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

extension EnvironmentValues {
    @Entry var openSidebar = OpenSidebarAction {}
}

/// Slide-out drawer shared by every destination: dimmed scrim, tap or swipe to close.
struct SidebarDrawer<Content: View, Drawer: View>: View {
    @Binding var isOpen: Bool
    /// Off where pushed screens own the leading edge for the back swipe.
    var opensOnEdgeSwipe = true
    @ViewBuilder let content: Content
    @ViewBuilder let drawer: Drawer

    var body: some View {
        ZStack(alignment: .leading) {
            content
                .disabled(isOpen)
                .environment(\.openSidebar, OpenSidebarAction { setOpen(true) })

            if isOpen {
                Color.black.opacity(0.36)
                    .ignoresSafeArea()
                    .onTapGesture { setOpen(false) }
                    .transition(.opacity)
                    .zIndex(1)

                drawer
                    .frame(width: 304)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(
                        Color(.secondarySystemGroupedBackground)
                            .ignoresSafeArea()
                    )
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.07))
                            .frame(width: 0.5)
                            .ignoresSafeArea()
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, x: 5, y: 0)
                    .transition(.move(edge: .leading))
                    .zIndex(2)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onEnded { value in
                    if opensOnEdgeSwipe && !isOpen && value.startLocation.x < 32 && value.translation.width > 64 {
                        setOpen(true)
                    } else if isOpen && value.translation.width < -60 {
                        setOpen(false)
                    }
                }
        )
    }

    private func setOpen(_ open: Bool) {
        dismissKeyboard()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isOpen = open
        }
    }
}

/// Drawer holding only the app navigation, for destinations without their own sidebar content.
struct AppNavigationDrawer<Content: View>: View {
    @Binding var selection: AppTab
    @ViewBuilder let content: Content
    @State private var isOpen = false

    var body: some View {
        SidebarDrawer(isOpen: $isOpen, opensOnEdgeSwipe: false) {
            content
        } drawer: {
            AppNavigationSection(selection: $selection) {
                isOpen = false
            }
        }
    }
}

/// The four app destinations, shown at the top of every sidebar.
struct AppNavigationSection: View {
    @Binding var selection: AppTab
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                row(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func row(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            if !isSelected {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selection = tab
                onSelect()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .frame(width: 22)
                Text(tab.title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.11) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Leading top-bar button that opens the enclosing sidebar.
struct SidebarButton: View {
    @Environment(\.openSidebar) private var openSidebar

    var body: some View {
        Button {
            openSidebar()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 16.5, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开侧边栏")
    }
}
