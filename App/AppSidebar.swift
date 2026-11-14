import Observation
import SwiftUI
import UIKit

/// Coordinates Level-1 tab selection, Level-2+ stack depth visibility for the bottom floating capsule,
/// global project filter synchronization, and the centered `+` New Thread trigger.
@MainActor
@Observable
final class WorkspaceNavigationStore {
    static let bottomDockClearance: CGFloat = 78

    var selection: AppTab = .conversations
    var selectedProjectID: String?
    var conversationsDepth: Int = 0
    var boardDepth: Int = 0
    var spaceDepth: Int = 0
    var settingsDepth: Int = 0
    var collabUnreadCount: Int = 0
    var newThreadTrigger: Int = 0

    var isCurrentTabAtRoot: Bool {
        switch selection {
        case .conversations:
            return conversationsDepth == 0
        case .board:
            return boardDepth == 0
        case .space:
            return spaceDepth == 0
        case .settings:
            return settingsDepth == 0
        }
    }

    func triggerNewThread() {
        selection = .conversations
        newThreadTrigger &+= 1
    }
}

// MARK: - Bottom Floating Symmetrical Capsule Dock (Level-1 Only)

/// Level-1 floating capsule navigation dock:
/// - On `.conversations`: `[ 会话 ] [ 看板 ] [ (+) ] [ 协作 ] [ 设置 ]`
/// - On `.board / .space / .settings`: `[ (+ ) ]` animates to zero width & zero gap so the 4 tabs
///   smoothly expand to 4 equal widths without leaving any blank space in the middle.
struct FloatingWorkspaceCapsuleDock: View {
    @Bindable var navStore: WorkspaceNavigationStore
    var attentionCount: Int = 0
    @Namespace private var tabHighlightNamespace

    private var showComposeButton: Bool {
        navStore.selection == .conversations
    }

    var body: some View {
        HStack(spacing: 0) {
            capsuleTabButton(.conversations, badgeCount: attentionCount)
            capsuleTabButton(.board)

            ZStack {
                if showComposeButton {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        navStore.triggerNewThread()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(.systemBackground))
                            .frame(width: 42, height: 42)
                            .background(
                                Circle()
                                    .fill(Color.primary)
                                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
                            )
                    }
                    .buttonStyle(DockScaleButtonStyle())
                    .accessibilityLabel("新建会话")
                    .transition(.scale(scale: 0.35).combined(with: .opacity))
                }
            }
            .frame(width: showComposeButton ? 54 : 0, height: 48)
            .clipped()

            capsuleTabButton(.space, badgeCount: navStore.collabUnreadCount)
            capsuleTabButton(.settings)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: showComposeButton)
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: navStore.selection)
    }

    private func capsuleTabButton(_ tab: AppTab, badgeCount: Int = 0) -> some View {
        let isSelected = navStore.selection == tab
        return Button {
            if !isSelected {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                navStore.selection = tab
            }
        } label: {
            VStack(spacing: 2.5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                        .font(.system(size: 16.5, weight: isSelected ? .semibold : .medium))
                        .frame(width: 24, height: 20)

                    if badgeCount > 0 {
                        Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                            .font(.system(size: 9.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4.5)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(x: 9, y: -5)
                    }
                }

                Text(tab.title)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                        .matchedGeometryEffect(id: "activeCapsuleTab", in: tabHighlightNamespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shared Level-2 Floating Header Chrome

/// Circular `<` back button used by Level-2 workspace screens (`新建会话` and `会话详情`).
struct FloatingCircleBackButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismissKeyboard()
            action()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.65)
                )
        }
        .buttonStyle(DockScaleButtonStyle())
        .accessibilityLabel("返回")
    }
}

/// Top-right unified dual-icon capsule `[ ⑂ 代码变更 | 📁 项目文件 ]` used on Level-2 workspace screens.
struct WorkspaceDualToolsCapsule: View {
    var changeCount: Int = 0
    var isDisabled: Bool = false
    let onOpenChanges: () -> Void
    let onOpenFiles: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissKeyboard()
                onOpenChanges()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 40)
                        .contentShape(Rectangle())

                    if changeCount > 0 {
                        Text(changeCount > 99 ? "99" : "\(changeCount)")
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(Capsule().fill(Color.orange))
                            .offset(x: -4, y: 5)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityLabel(changeCount > 0 ? "代码差异（\(changeCount) 处改动）" : "代码差异")

            Rectangle()
                .fill(Color.primary.opacity(0.09))
                .frame(width: 0.65, height: 18)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismissKeyboard()
                onOpenFiles()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityLabel("浏览项目文件")
        }
        .padding(.horizontal, 2)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.65)
        )
        .opacity(isDisabled ? 0.45 : 1)
    }
}

private struct DockScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.15), value: configuration.isPressed)
    }
}
