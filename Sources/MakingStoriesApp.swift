import AVFoundation
import AppKit
import SwiftUI

@main
struct MakingStoriesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("MakingStories", id: "main") {
            ContentView()
                .environmentObject(delegate.model)
                .frame(minWidth: 860, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Video…") { delegate.model.choose() }
                    .keyboardShortcut("o")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = EditorModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--export"), args.count > i + 6 else { return }
        headless(source: URL(fileURLWithPath: args[i + 1]),
                 output: URL(fileURLWithPath: args[i + 2]),
                 start: Double(args[i + 3]) ?? 0,
                 end: Double(args[i + 4]) ?? 0,
                 offset: CGPoint(x: Double(args[i + 5]) ?? 0.5, y: Double(args[i + 6]) ?? 0.5))
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { model.load(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// `MakingStories --export <in> <out> <start> <end> <offsetX> <offsetY>` — one clip, no window.
    private func headless(source: URL, output: URL, start: Double, end: Double, offset: CGPoint) {
        Task {
            do {
                let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                        end: CMTime(seconds: end, preferredTimescale: 600))
                try await Exporter.export(source: source, range: range, offset: offset, to: output)
                print(output.path)
            } catch {
                print("failed: \(error.localizedDescription)")
            }
            NSApp.terminate(nil)
        }
    }
}
