import SwiftUI
import AppKit

@main
struct InkSealApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DocumentStore()

    var body: some Scene {
        WindowGroup("InkSeal", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1180, minHeight: 720)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.saveNow()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Document…") { store.showNewDocument = true }
                    .keyboardShortcut("n")
                Button("Import PDF…") { store.importURLs(Panels.choosePDFs()) }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct SettingsView: View {
    @EnvironmentObject private var store: DocumentStore
    @State private var capture: FieldKind?

    var body: some View {
        Form {
            Section("Your Profile") {
                TextField("Full name", text: $store.profile.name)
                TextField("Email", text: $store.profile.email)
                Text("Used when you sign your own documents and in the audit trail.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Saved Signature") {
                signatureRow(.signature, data: store.profile.signature)
                signatureRow(.initials, data: store.profile.initials)
            }
            Section("Storage") {
                LabeledContent("Library") {
                    Text(store.root.path).font(.caption).textSelection(.enabled)
                }
                Button("Show Library in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.root])
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 480)
        .sheet(item: $capture) { kind in
            SignatureCaptureView(kind: kind, name: store.profile.name) { data, _ in
                if kind == .initials { store.profile.initials = data } else { store.profile.signature = data }
            }
        }
    }

    private func signatureRow(_ kind: FieldKind, data: Data?) -> some View {
        HStack {
            Text(kind.title)
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.white)
                if let data, let img = NSImage(data: data) {
                    Image(nsImage: img).resizable().scaledToFit().padding(4)
                } else {
                    Text("None").font(.caption).foregroundStyle(.gray)
                }
            }
            .frame(width: 160, height: 44)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
            Button(data == nil ? "Adopt…" : "Change…") { capture = kind }
            if data != nil {
                Button("Remove") {
                    if kind == .initials { store.profile.initials = nil } else { store.profile.signature = nil }
                }
            }
        }
    }
}
