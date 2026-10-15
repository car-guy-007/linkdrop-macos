import AppKit
import SwiftUI
import Foundation

enum Quality: String, CaseIterable, Identifiable {
    case best = "Best available"
    case hd1080 = "Up to 1080p"
    case hd720 = "Up to 720p"
    case audio = "Audio (MP3)"
    var id: String { rawValue }
    var args: [String] {
        switch self {
        case .best: return ["-f", "bv*+ba/b", "--merge-output-format", "mp4/mkv"]
        case .hd1080: return ["-f", "bv*[height<=1080]+ba/b[height<=1080]/b", "--merge-output-format", "mp4/mkv"]
        case .hd720: return ["-f", "bv*[height<=720]+ba/b[height<=720]/b", "--merge-output-format", "mp4/mkv"]
        case .audio: return ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        }
    }
}

enum Browser: String, CaseIterable, Identifiable {
    case none = "None"
    case safari = "Safari"
    case chrome = "Chrome"
    case firefox = "Firefox"
    case brave = "Brave"
    case edge = "Edge"
    var id: String { rawValue }
    var argument: String? { self == .none ? nil : rawValue.lowercased() }
}

@MainActor
final class DownloadManager: ObservableObject {
    @Published var link = ""
    @Published var quality: Quality = .best
    @Published var browser: Browser = .none
    @Published var playlist = false
    @Published private(set) var destination: URL
    @Published private(set) var running = false
    @Published private(set) var updating = false
    @Published private(set) var fraction = 0.0
    @Published private(set) var status = "Paste a video link to begin."
    @Published private(set) var log = ""
    @Published private(set) var savedFile: URL?
    @Published private(set) var completed = false
    private var job: Process?
    private var buffer = ""
    private var lines = [String]()
    private var stopped = false

    init() {
        let standard = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        if let path = UserDefaults.standard.string(forKey: "LinkDrop.saveFolder"),
           FileManager.default.fileExists(atPath: path) {
            destination = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            destination = standard
        }
    }

    private var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }
    private var tools: URL? { Bundle.main.resourceURL?.appendingPathComponent("tools") }
    private var updateCopy: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LinkDrop/yt-dlp_macos")
    }
    private static func installed(_ name: String) -> String? {
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] +
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return dirs.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    private var ytDlp: String? {
        if FileManager.default.isExecutableFile(atPath: updateCopy.path) { return updateCopy.path }
        if let path = tools?.appendingPathComponent("yt-dlp_macos").path,
           FileManager.default.isExecutableFile(atPath: path) { return path }
        return Self.installed("yt-dlp")
    }
    private var ffmpegFolder: String? {
        if let path = tools?.appendingPathComponent("\(arch)/ffmpeg").path,
           FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path).deletingLastPathComponent().path }
        if let path = Self.installed("ffmpeg") { return URL(fileURLWithPath: path).deletingLastPathComponent().path }
        return nil
    }
    private var deno: String? {
        if let path = tools?.appendingPathComponent("\(arch)/deno").path,
           FileManager.default.isExecutableFile(atPath: path) { return path }
        return Self.installed("deno")
    }
    var ready: Bool { ytDlp != nil && ffmpegFolder != nil }
    var busy: Bool { running || updating }
    var canStart: Bool { ready && !busy && !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func paste() {
        if let text = NSPasteboard.general.string(forType: .string) {
            link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        panel.prompt = "Save here"
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
            UserDefaults.standard.set(url.path, forKey: "LinkDrop.saveFolder")
        }
    }
    func showFolder() {
        if let savedFile, FileManager.default.fileExists(atPath: savedFile.path) {
            NSWorkspace.shared.activateFileViewerSelecting([savedFile])
        } else { NSWorkspace.shared.open(destination) }
    }
    func start() {
        guard !busy else { return }
        let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLComponents(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            status = "Please paste a valid video URL starting with https://"
            return
        }
        guard let ytDlp, let ffmpegFolder else {
            status = "Download tools not found. Install the packaged Mac build."
            return
        }
        guard FileManager.default.isWritableFile(atPath: destination.path) else {
            status = "No write access to this folder. Choose another."
            return
        }
        var args = [
            "--ignore-config", "--no-simulate", "--continue", "--no-overwrites",
            "--newline", "--no-colors", "--progress",
            "--progress-template", "download:LINKDROP_PROGRESS|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
            "--print", "after_move:LINKDROP_FILE:%(filepath)s",
            "--ffmpeg-location", ffmpegFolder,
            "--paths", destination.path,
            "-o", "%(title).160B [%(id)s].%(ext)s",
            "--socket-timeout", "25", "--retries", "10", "--fragment-retries", "10",
            "--retry-sleep", "http:exp=1:12", "--retry-sleep", "fragment:exp=1:8",
            "--concurrent-fragments", "4", "--restrict-filenames"
        ]
        args.append(playlist ? "--yes-playlist" : "--no-playlist")
        if let chosenBrowser = browser.argument {
            args += ["--cookies-from-browser", chosenBrowser]
        }
        if let deno {
            args += ["--js-runtimes", "deno:\(deno)", "--remote-components", "ejs:github"]
        }
        args += quality.args
        args += ["--", value]
        begin(executable: ytDlp, args: args, isUpdate: false)
    }
    func stop() {
        guard running, let job else { return }
        stopped = true
        status = "Stopping…"
        if job.isRunning { job.terminate() }
    }
    func updateEngine() {
        guard !busy, let ytDlp else { return }
        do {
            try FileManager.default.createDirectory(at: updateCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
            if ytDlp != updateCopy.path {
                if FileManager.default.fileExists(atPath: updateCopy.path) {
                    try FileManager.default.removeItem(at: updateCopy)
                }
                try FileManager.default.copyItem(atPath: ytDlp, toPath: updateCopy.path)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: updateCopy.path)
            }
        } catch {
            status = "Update setup failed: \(error.localizedDescription)"
            return
        }
        begin(executable: updateCopy.path, args: ["--no-colors", "--update-to", "stable"], isUpdate: true)
    }
    private func begin(executable: String, args: [String], isUpdate: Bool) {
        log = ""
        lines.removeAll()
        buffer = ""
        fraction = 0
        savedFile = nil
        completed = false
        stopped = false
        running = !isUpdate
        updating = isUpdate
        status = isUpdate ? "Updating website compatibility…" : "Connecting to website…"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = destination
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        job = process
        do {
            try process.run()
        } catch {
            job = nil; running = false; updating = false
            status = "Unable to launch downloader: \(error.localizedDescription)"
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let reader = pipe.fileHandleForReading
            while true {
                let data = reader.availableData
                if data.isEmpty { break }
                DispatchQueue.main.async { [weak self] in self?.read(data, isUpdate: isUpdate) }
            }
            process.waitUntilExit()
            DispatchQueue.main.async { [weak self] in
                self?.finish(code: process.terminationStatus, isUpdate: isUpdate)
            }
        }
    }
    private func read(_ data: Data, isUpdate: Bool) {
        buffer += String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r", with: "\n")
        let segments = buffer.components(separatedBy: "\n")
        buffer = segments.last ?? ""
        for line in segments.dropLast() { handle(line, isUpdate: isUpdate) }
        if buffer.count > 12000 { buffer = String(buffer.suffix(12000)) }
    }
    private func handle(_ text: String, isUpdate: Bool) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        lines.append(line)
        if lines.count > 70 { lines.removeFirst(lines.count - 70) }
        log = lines.joined(separator: "\n")
        if isUpdate { return }
        if let range = line.range(of: "LINKDROP_PROGRESS|") {
            let parts = line[range.upperBound...].split(separator: "|", omittingEmptySubsequences: false)
            if let first = parts.first,
               let p = Double(first.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) {
                fraction = max(0, min(1, p / 100))
            }
            status = "Downloading · \(Int(fraction * 100))%"
            if parts.count > 1 && parts[1] != "NA" { status += " · \(parts[1])" }
            if parts.count > 2 && parts[2] != "NA" { status += " · \(parts[2]) remaining" }
        } else if line.hasPrefix("LINKDROP_FILE:") {
            let path = String(line.dropFirst("LINKDROP_FILE:".count))
            if FileManager.default.fileExists(atPath: path) { savedFile = URL(fileURLWithPath: path) }
        } else if line.contains("[Merger]") || line.contains("[ExtractAudio]") {
            status = "Finishing media file…"
        }
    }
    private func finish(code: Int32, isUpdate: Bool) {
        if !buffer.isEmpty { handle(buffer, isUpdate: isUpdate); buffer = "" }
        job = nil
        if isUpdate {
            updating = false
            status = code == 0 ? "Download engine is up to date." : "Update failed; see Activity log."
            return
        }
        running = false
        if stopped { status = "Stopped. Press Download to retry or resume." }
        else if code == 0 { completed = true; fraction = 1; status = "Finished! Open your download folder." }
        else {
            let details = lines.suffix(25).joined(separator: " ").lowercased()
            if details.contains("drm") { status = "DRM-protected videos are not supported." }
            else if details.contains("unsupported url") { status = "This video site or link is not supported." }
            else if details.contains("429") || details.contains("too many requests") { status = "The site is rate-limiting. Retry later." }
            else if details.contains("sign in") || details.contains("login") || details.contains("cookies") { status = "Sign-in may be required; try Browser login." }
            else if details.contains("403") || details.contains("forbidden") { status = "Access denied. Verify URL and permissions." }
            else if details.contains("timed out") || details.contains("connection") { status = "Network interrupted. Press Download to retry." }
            else { status = "Could not download. Try Update engine or check Activity log." }
        }
    }
}

struct ContentView: View {
    @StateObject private var model = DownloadManager()
    @State private var showLog = false
    private let accent = Color(red: 0.12, green: 0.72, blue: 0.62)
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 48)).foregroundColor(accent)
                VStack(alignment: .leading) {
                    Text("LinkDrop").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Paste a link. Save your video.").foregroundColor(.secondary)
                }
                Spacer()
                Button("Update engine") { model.updateEngine() }
                    .disabled(model.busy || !model.ready)
            }
            Text("VIDEO LINK").font(.caption.bold()).foregroundColor(.secondary)
            HStack {
                TextField("https://example.com/video", text: $model.link)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.start() }
                    .disabled(model.busy)
                Button("Paste") { model.paste() }.disabled(model.busy)
            }
            VStack(spacing: 14) {
                HStack {
                    Label("Quality", systemImage: "film")
                    Spacer()
                    Picker("Quality", selection: $model.quality) {
                        ForEach(Quality.allCases) { item in Text(item.rawValue).tag(item) }
                    }.labelsHidden().frame(width: 170).disabled(model.busy)
                }
                Divider()
                HStack {
                    Label("Save to", systemImage: "folder")
                    Spacer()
                    Text(model.destination.lastPathComponent).lineLimit(1).foregroundColor(.secondary)
                    Button("Change…") { model.selectFolder() }.disabled(model.busy)
                }
                Divider()
                HStack {
                    Label("Browser login", systemImage: "person.crop.circle")
                    Spacer()
                    Picker("Browser login", selection: $model.browser) {
                        ForEach(Browser.allCases) { item in Text(item.rawValue).tag(item) }
                    }.labelsHidden().frame(width: 170).disabled(model.busy)
                }
                Toggle("Download entire playlist", isOn: $model.playlist).disabled(model.busy)
            }
            .padding(16)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 12) {
                Label(model.status, systemImage: model.completed ? "checkmark.circle.fill" : "info.circle")
                    .font(.subheadline)
                if model.running {
                    ProgressView(value: model.fraction).tint(accent)
                } else if model.updating {
                    ProgressView()
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            HStack {
                if model.running {
                    Button("Stop") { model.stop() }.controlSize(.large)
                } else {
                    Button("Download") { model.start() }
                        .buttonStyle(.borderedProminent).tint(accent)
                        .disabled(!model.canStart).controlSize(.large)
                }
                Button(model.completed ? "Show file" : "Open folder") { model.showFolder() }
                    .controlSize(.large)
            }
            if !model.ready {
                Text("Download helpers are missing; use the bundled macOS app from GitHub Actions.")
                    .font(.caption).foregroundColor(.orange)
            }
            DisclosureGroup("Activity log · troubleshooting", isExpanded: $showLog) {
                ScrollView {
                    Text(model.log.isEmpty ? "Details appear here during downloads." : model.log)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled).padding(.vertical, 8)
                }.frame(maxHeight: 130)
            }.font(.caption)
            Spacer(minLength: 0)
            Text("Downloads run locally · Browser login is opt-in · No DRM bypass")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(28).frame(minWidth: 650, minHeight: 610)
    }
}

@main
struct LinkDropApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .defaultSize(width: 720, height: 650)
    }
}
