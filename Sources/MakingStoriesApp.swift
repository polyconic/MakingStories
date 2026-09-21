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
        if let i = args.firstIndex(of: "--track-export"), args.count > i + 4 {
            trackHeadless(source: URL(fileURLWithPath: args[i + 1]),
                          output: URL(fileURLWithPath: args[i + 2]),
                          start: Double(args[i + 3]) ?? 0,
                          end: Double(args[i + 4]) ?? 0)
            return
        }
        if let i = args.firstIndex(of: "--pan-export"), args.count > i + 6 {
            // A known linear pan, for checking the transform ramps without involving detection.
            let (start, end) = (Double(args[i + 3]) ?? 0, Double(args[i + 4]) ?? 0)
            let (x0, x1) = (Double(args[i + 5]) ?? 0.5, Double(args[i + 6]) ?? 0.5)
            let steps = 20
            let points = (0...steps).map { s -> TrackPoint in
                let f = Double(s) / Double(steps)
                return TrackPoint(time: start + (end - start) * f,
                                  subject: CGPoint(x: x0 + (x1 - x0) * f, y: 0.5))
            }
            panHeadless(source: URL(fileURLWithPath: args[i + 1]),
                        output: URL(fileURLWithPath: args[i + 2]),
                        start: start, end: end, pan: points)
            return
        }
        guard let i = args.firstIndex(of: "--export"), args.count > i + 6 else { return }
        headless(source: URL(fileURLWithPath: args[i + 1]),
                 output: URL(fileURLWithPath: args[i + 2]),
                 start: Double(args[i + 3]) ?? 0,
                 end: Double(args[i + 4]) ?? 0,
                 offset: CGPoint(x: Double(args[i + 5]) ?? 0.5, y: Double(args[i + 6]) ?? 0.5),
                 zoom: args.count > i + 7 ? CGFloat(Double(args[i + 7]) ?? 1) : 1)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { model.load(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func panHeadless(source: URL, output: URL, start: Double, end: Double,
                             pan: [TrackPoint]) {
        Task {
            do {
                let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                        end: CMTime(seconds: end, preferredTimescale: 600))
                try await Exporter.export(source: source, range: range,
                                          offset: CGPoint(x: 0.5, y: 0.5), pan: pan, to: output)
                print(output.path)
            } catch {
                print("failed: \(error.localizedDescription)")
            }
            NSApp.terminate(nil)
        }
    }

    /// `MakingStories --track-export <in> <out> <start> <end>` — track the subject, then export.
    private func trackHeadless(source: URL, output: URL, start: Double, end: Double) {
        Task {
            do {
                let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                        end: CMTime(seconds: end, preferredTimescale: 600))
                let points = try await Tracker.track(source: source, range: range) { _ in }
                print("tracked \(points.count) points")
                for p in points.prefix(4) {
                    print(String(format: "  t=%.2f subject=(%.3f, %.3f)", p.time, p.subject.x, p.subject.y))
                }
                try await Exporter.export(source: source, range: range,
                                          offset: CGPoint(x: 0.5, y: 0.5), pan: points, to: output)
                print(output.path)
            } catch {
                print("failed: \(error.localizedDescription)")
            }
            NSApp.terminate(nil)
        }
    }

    /// `MakingStories --export <in> <out> <start> <end> <offsetX> <offsetY> [zoom]` — one clip, no window.
    private func headless(source: URL, output: URL, start: Double, end: Double,
                          offset: CGPoint, zoom: CGFloat) {
        Task {
            do {
                let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                        end: CMTime(seconds: end, preferredTimescale: 600))
                try await Exporter.export(source: source, range: range, offset: offset,
                                          zoom: zoom, to: output)
                print(output.path)
            } catch {
                print("failed: \(error.localizedDescription)")
            }
            NSApp.terminate(nil)
        }
    }
}
