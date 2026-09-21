import AppKit
import SwiftUI

struct TabBar: View {
    @EnvironmentObject private var store: DocumentStore

    var body: some View {
        HStack(spacing: 0) {
            // Room for the traffic lights, since the title bar is hidden.
            Color.clear.frame(width: 72, height: 1)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(store.documents) { document in
                            TabChip(
                                document: document,
                                isSelected: document.id == store.selectedID,
                                select: { store.selectedID = document.id },
                                close: { store.close(document) }
                            )
                            .id(document.id)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onChange(of: store.selectedID) { id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id) }
                }
            }

            Button(action: { store.newDocument() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .help("New Document (⌘N)")
            .padding(.horizontal, 6)
        }
        .frame(height: 38)
        .background(Color(nsColor: MarkdownTheme.chrome))
    }
}

private struct TabChip: View {
    @ObservedObject var document: MarkdownDocument
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            closeOrDot
            Text(document.displayName)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .frame(minWidth: 96, maxWidth: 210)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .help(document.url?.path ?? "Not saved")
        .contextMenu {
            Button("Close Tab") { close() }
            if let url = document.url {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
            }
        }
    }

    /// One slot holds either the unsaved dot or the close button: the dot turns
    /// into the button when you point at it, which is where you'd click anyway.
    @ViewBuilder
    private var closeOrDot: some View {
        if isHovering {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 13, height: 13)
            }
            .buttonStyle(.plain)
            .help("Close Tab (⌘W)")
        } else if document.isDirty {
            Circle()
                .fill(Color.secondary)
                .frame(width: 6, height: 6)
                .frame(width: 13, height: 13)
        } else {
            Color.clear.frame(width: 13, height: 13)
        }
    }

    private var background: Color {
        if isSelected { return Color(nsColor: MarkdownTheme.editorBackground) }
        if isHovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}
