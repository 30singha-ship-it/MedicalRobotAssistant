//
//  MedAssist_iOS_FINAL.swift
//  MedAssist Hospital Command — FINAL professional build.
//
//  New in this version:
//   - Branded launch screen (logo + name) replaces the blank black screen
//     that appeared on cold start before the camera/video view painted.
//   - A dedicated "Vitals" patient-monitor tab decoding the ESP32's new
//     {"TYPE":"vitals",...} stream: motion, immobility timer, pallor and
//     cyanosis visual-cue scores — all explicitly labeled as AI visual
//     cues for a caregiver to verify, never presented as a diagnosis.
//   - Same core connection manager, drive controls, autonomous mode, and
//     diagnostics as before; nothing that already worked was changed.
//
import SwiftUI
import UIKit
import Combine
import Photos

// MARK: - App Entry

@main
struct MedAssistApp: App {
    @StateObject private var robot = RobotConnectionManager()

    var body: some Scene {
        WindowGroup {
            LaunchGate()
                .environmentObject(robot)
                .preferredColorScheme(.dark)
                .tint(ClinicalTheme.teal)
        }
    }
}

/// Shows a branded splash for a beat, then swaps to the real command center.
/// This directly replaces the "blank black" first-launch impression.
struct LaunchGate: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
            } else {
                CommandCenterView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
            }
        }
    }
}

struct SplashView: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [ClinicalTheme.navy, Color(red: 0.02, green: 0.03, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                MedAssistLogo()
                    .scaleEffect(pulse ? 1.05 : 0.92)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                VStack(spacing: 4) {
                    Text("MEDASSIST").font(.title2.bold().monospaced()).foregroundStyle(.white)
                    Text("HOSPITAL ROBOTICS COMMAND").font(.caption.bold().monospaced()).foregroundStyle(ClinicalTheme.teal)
                }
                ProgressView().tint(ClinicalTheme.teal).padding(.top, 6)
            }
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Clinical Brand & Theme

enum ClinicalTheme {
    static let navy = Color(red: 0.025, green: 0.055, blue: 0.098)
    static let panel = Color(red: 0.055, green: 0.110, blue: 0.180)
    static let panelRaised = Color(red: 0.072, green: 0.145, blue: 0.227)
    static let teal = Color(red: 0.000, green: 0.810, blue: 0.720)
    static let green = Color(red: 0.220, green: 0.850, blue: 0.470)
    static let amber = Color(red: 1.000, green: 0.690, blue: 0.140)
    static let red = Color(red: 0.960, green: 0.250, blue: 0.310)
    static let muted = Color.white.opacity(0.58)
}

struct MedAssistLogo: View {
    var compact = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 11 : 20, style: .continuous)
                .fill(LinearGradient(colors: [ClinicalTheme.teal, Color(red: 0, green: 0.45, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: compact ? 11 : 20, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 1)
            Image(systemName: "cross.case.fill")
                .font(.system(size: compact ? 18 : 36, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: compact ? 40 : 84, height: compact ? 40 : 84)
        .shadow(color: ClinicalTheme.teal.opacity(0.35), radius: 14, y: 6)
        .accessibilityLabel("MedAssist Medical Robotics")
    }
}

struct ClinicalCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(ClinicalTheme.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.075), lineWidth: 1))
    }
}
extension View { func clinicalCard(_ padding: CGFloat = 16) -> some View { modifier(ClinicalCard(padding: padding)) } }

// MARK: - Wire Protocol Models

struct GyroReading: Codable { let ax, ay, az, gx, gy, gz: Double }

struct RobotTelemetry: Codable {
    let T: Int
    let US: Double
    let LT: [Int]
    let GY: GyroReading
    let TIPPED: Int
    let BATT: Double?
    let MODE: String?
    var isTipped: Bool { TIPPED != 0 }
    var hasDistance: Bool { US > 0 }
    var isAutonomous: Bool { MODE == "patrol" }
}

struct DetectedObject: Codable, Identifiable {
    var id = UUID()
    let label: String
    let conf, x, y, w, h: Double
    enum CodingKeys: String, CodingKey { case label, conf, x, y, w, h }
}

struct DetectionFrame: Codable { let TYPE: String; let T: Int; let objects: [DetectedObject] }
struct Heartbeat: Codable { let TYPE: String; let uptime_s, rssi, clients: Int; let camera: Bool? }
struct HealthStatus: Codable {
    let status, ap_ssid, ap_ip: String
    let ap_clients: Int
    let camera_ok, psram: Bool
    let free_heap, uptime_s: Int
    let sta_connected: Bool
    let sta_ip: String?
}

/// NEW: decodes the ESP32's {"TYPE":"vitals", ...} messages.
struct VitalsFrame: Codable {
    let TYPE: String
    let T: Int
    let person_present: Bool
    let motion_score: Double
    let immobility_sec: Double
    let agitation_sec: Double
    let pallor_score: Double
    let cyanosis_score: Double
    let immobility_alert: Bool
    let agitation_alert: Bool
    let disclaimer: String
}

struct Incident: Identifiable {
    let id = UUID()
    let date: Date
    let title: String
    let confidence: Double
}

struct RobotCommand: Codable { var H, N: Int; var D1, D2, D3: Int? }
enum DriveDirection: Int { case left = 1, right = 2, forward = 3, reverse = 4 }

enum Commands {
    private static var sequence = 100
    private static func id() -> Int { sequence += 1; return sequence }
    static func drive(_ direction: DriveDirection, speed: Int) -> RobotCommand { RobotCommand(H: id(), N: 3, D1: direction.rawValue, D2: speed, D3: nil) }
    static func servo(_ id: Int, _ degrees: Int) -> RobotCommand { RobotCommand(H: self.id(), N: 5, D1: id, D2: degrees, D3: nil) }
    static func stop() -> RobotCommand { RobotCommand(H: id(), N: 100, D1: nil, D2: nil, D3: nil) }
    static func autonomous(_ enabled: Bool) -> RobotCommand { RobotCommand(H: id(), N: 101, D1: enabled ? 1 : 0, D2: nil, D3: nil) }
    static func guardEnabled(_ enabled: Bool) -> RobotCommand { RobotCommand(H: id(), N: 900, D1: enabled ? 1 : 0, D2: nil, D3: nil) }
    static func reminder(_ minutes: Int) -> RobotCommand { RobotCommand(H: id(), N: 901, D1: minutes, D2: nil, D3: nil) }
    static func buzzer() -> RobotCommand { RobotCommand(H: id(), N: 902, D1: 2, D2: nil, D3: nil) }
}

enum ConnectionPhase: Equatable {
    case offline, connecting, online, warning, unavailable(String)
    var title: String {
        switch self { case .offline: return "OFFLINE"; case .connecting: return "CONNECTING"; case .online: return "LIVE"; case .warning: return "DEGRADED"; case .unavailable: return "UNREACHABLE" }
    }
    var color: Color {
        switch self { case .offline: return .gray; case .connecting, .warning: return ClinicalTheme.amber; case .online: return ClinicalTheme.green; case .unavailable: return ClinicalTheme.red }
    }
}

// MARK: - Connection / Mission State

@MainActor
final class RobotConnectionManager: NSObject, ObservableObject {
    @Published var phase: ConnectionPhase = .offline
    @Published var robotHost = "192.168.4.1"
    @Published var telemetry: RobotTelemetry?
    @Published var detections: [DetectedObject] = []
    @Published var incidents: [Incident] = []
    @Published var heartbeat: Heartbeat?
    @Published var health: HealthStatus?
    @Published var vitals: VitalsFrame?
    @Published var autonomous = false
    @Published var lastMessageAt: Date?

    var isOnline: Bool { phase == .online || phase == .warning }
    var streamURL: URL? { URL(string: "http://\(robotHost)/stream") }
    var healthURL: URL? { URL(string: "http://\(robotHost)/health") }

    private var socket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var retryTimer: Timer?
    private var healthTimer: Timer?
    private var detectionTimer: Timer?
    private var retrySeconds: TimeInterval = 1
    private var intentionalDisconnect = false
    private let haptics = UINotificationFeedbackGenerator()

    func connect() {
        intentionalDisconnect = false
        guard let url = URL(string: "ws://\(robotHost)/ws") else { phase = .unavailable("Bad address"); return }
        phase = .connecting
        socket?.cancel(with: .goingAway, reason: nil)
        socket = session.webSocketTask(with: url)
        socket?.resume()
        readLoop()
        pollHealth()
        beginMonitoring()
    }

    func disconnect() {
        intentionalDisconnect = true
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        phase = .offline
        retryTimer?.invalidate()
        healthTimer?.invalidate()
    }

    private func readLoop() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .failure(let error):
                    self.phase = .unavailable(self.networkError(error))
                    self.retry()
                case .success(let message):
                    let string: String?
                    switch message { case .string(let s): string = s; case .data(let d): string = String(data: d, encoding: .utf8); @unknown default: string = nil }
                    if let string { self.consume(string) }
                    self.readLoop()
                }
            }
        }
    }

    private func consume(_ text: String) {
        lastMessageAt = Date()
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        if text.contains("\"TYPE\":\"heartbeat\"") || text.contains("\"TYPE\": \"heartbeat\"") {
            if let hb = try? decoder.decode(Heartbeat.self, from: data) { heartbeat = hb; phase = .online; retrySeconds = 1 }
        } else if text.contains("\"TYPE\":\"detections\"") || text.contains("\"TYPE\": \"detections\"") {
            if let f = try? decoder.decode(DetectionFrame.self, from: data) {
                detections = f.objects
                f.objects.forEach { object in
                    incidents.insert(Incident(date: Date(), title: object.label, confidence: object.conf), at: 0)
                    if object.label == "possible_fall" { haptics.notificationOccurred(.warning) }
                }
                if incidents.count > 60 { incidents.removeLast(incidents.count - 60) }
                clearStaleDetections()
            }
        } else if text.contains("\"TYPE\":\"vitals\"") || text.contains("\"TYPE\": \"vitals\"") {
            if let v = try? decoder.decode(VitalsFrame.self, from: data) {
                let wasAlert = vitals?.immobility_alert ?? false
                vitals = v
                if v.immobility_alert && !wasAlert { haptics.notificationOccurred(.warning) }
            }
        } else if text.contains("\"US\"") {
            if let t = try? decoder.decode(RobotTelemetry.self, from: data) {
                let previouslyTipped = telemetry?.isTipped ?? false
                telemetry = t
                autonomous = t.isAutonomous
                if t.isTipped && !previouslyTipped { haptics.notificationOccurred(.error) }
            }
        }
    }

    private func beginMonitoring() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.evaluate() } }
    }

    private func evaluate() {
        pollHealth()
        guard let lastMessageAt else { return }
        if Date().timeIntervalSince(lastMessageAt) > 7 && socket?.state == .running { phase = .warning }
    }

    func pollHealth() {
        guard let url = healthURL else { return }
        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let h = try? JSONDecoder().decode(HealthStatus.self, from: data) else { return }
            Task { @MainActor in self?.health = h }
        }.resume()
    }

    private func retry() {
        guard !intentionalDisconnect else { return }
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: retrySeconds, repeats: false) { [weak self] _ in Task { @MainActor in self?.connect() } }
        retrySeconds = min(retrySeconds * 2, 12)
    }

    private func clearStaleDetections() {
        detectionTimer?.invalidate()
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: false) { [weak self] _ in Task { @MainActor in self?.detections = [] } }
    }

    private func networkError(_ error: Error) -> String {
        let code = (error as NSError).code
        if code == -1004 { return "Robot not found" }
        if code == -1001 { return "Timed out" }
        return "Link interrupted"
    }

    func send(_ command: RobotCommand) {
        guard let data = try? JSONEncoder().encode(command), let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { _ in }
    }
    func drive(_ direction: DriveDirection, speed: Int) { send(Commands.drive(direction, speed: speed)) }
    func stop() { send(Commands.stop()) }
    func setServo(_ id: Int, _ degrees: Int) { send(Commands.servo(id, degrees)) }
    func setGuard(_ enabled: Bool) { send(Commands.guardEnabled(enabled)) }
    func setReminder(_ minutes: Int) { send(Commands.reminder(minutes)) }
    func buzz() { send(Commands.buzzer()) }
    func engageAutonomy() { autonomous = true; send(Commands.autonomous(true)) }
    func endAutonomy() { autonomous = false; stop(); send(Commands.autonomous(false)) }
}

// MARK: - Main Navigation

struct CommandCenterView: View {
    var body: some View {
        TabView {
            MissionDashboard().tabItem { Label("Mission", systemImage: "cross.case.fill") }
            VideoCommandView().tabItem { Label("Observe", systemImage: "video.fill") }
            ManualDriveView().tabItem { Label("Drive", systemImage: "steeringwheel") }
            UnmannedModeView().tabItem { Label("Unmanned", systemImage: "brain.head.profile") }
            PatientMonitorView().tabItem { Label("Vitals", systemImage: "waveform.path.ecg") }
            SystemsView().tabItem { Label("Systems", systemImage: "gearshape.fill") }
        }
    }
}

struct LinkStrip: View {
    @EnvironmentObject var robot: RobotConnectionManager
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(robot.phase.color).frame(width: 8, height: 8)
            Text(robot.phase.title).font(.caption2.bold().monospaced())
            Spacer()
            Text(robot.robotHost).font(.caption2.monospaced()).foregroundStyle(ClinicalTheme.muted)
            if robot.phase != .online { Button("RETRY") { robot.connect() }.font(.caption2.bold()) }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(robot.phase.color.opacity(0.14))
    }
}

// MARK: - Mission Dashboard

struct MissionDashboard: View {
    @EnvironmentObject var robot: RobotConnectionManager

    var body: some View {
        NavigationStack {
            ZStack {
                ClinicalTheme.navy.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 15) {
                        LinkStrip()
                        missionHeader
                        metricGrid
                        responseRow
                        incidentPanel
                    }.padding(16)
                }
            }
            .navigationTitle("MedAssist Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { MedAssistLogo(compact: true) } }
            .onAppear { if !robot.isOnline { robot.connect() } }
        }
    }

    private var missionHeader: some View {
        HStack(spacing: 14) {
            MedAssistLogo()
            VStack(alignment: .leading, spacing: 4) {
                Text("UNIT MA-01").font(.caption.bold().monospaced()).foregroundStyle(ClinicalTheme.teal)
                Text(robot.autonomous ? "UNMANNED CARE PATROL" : "CLINICAL SUPPORT READY").font(.headline)
                Text(robot.autonomous ? "Autonomous sensor-guided navigation active" : "Secure manual operator control available")
                    .font(.caption).foregroundStyle(ClinicalTheme.muted)
            }
            Spacer()
        }.clinicalCard()
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metric("battery.75", "POWER", robot.telemetry?.BATT.map { String(format: "%.1f V", $0) } ?? "—", color: batteryColor)
            metric("ruler", "CLEARANCE", robot.telemetry?.hasDistance == true ? String(format: "%.0f cm", robot.telemetry!.US) : "—", color: ClinicalTheme.teal)
            metric("wifi", "LINK", robot.heartbeat.map { "\($0.rssi) dBm" } ?? "—", color: ClinicalTheme.teal)
            metric(robot.telemetry?.isTipped == true ? "exclamationmark.triangle.fill" : "checkmark.shield.fill", "SAFETY", robot.telemetry?.isTipped == true ? "ALERT" : "NOMINAL", color: robot.telemetry?.isTipped == true ? ClinicalTheme.red : ClinicalTheme.green)
        }
    }

    private var batteryColor: Color { (robot.telemetry?.BATT ?? 8) < 6.6 ? ClinicalTheme.red : ClinicalTheme.green }

    private func metric(_ icon: String, _ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2.bold().monospaced()).foregroundStyle(ClinicalTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).clinicalCard()
    }

    private var responseRow: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) { robot.stop() } label: {
                Label("E-STOP", systemImage: "octagon.fill").frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.borderedProminent).tint(ClinicalTheme.red)
            Button { robot.buzz() } label: {
                Label("CALL", systemImage: "bell.badge.fill").frame(maxWidth: .infinity).padding(.vertical, 12)
            }.buttonStyle(.bordered).tint(ClinicalTheme.teal)
        }
    }

    private var incidentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Label("AI INCIDENT QUEUE", systemImage: "eye.trianglebadge.exclamationmark").font(.caption.bold()); Spacer(); Text("\(robot.incidents.count)").font(.caption.monospacedDigit()).foregroundStyle(ClinicalTheme.muted) }
            if robot.incidents.isEmpty { Text("No clinical visual events recorded.").font(.caption).foregroundStyle(ClinicalTheme.muted) }
            ForEach(robot.incidents.prefix(3)) { incident in
                HStack { Circle().fill(incident.title == "possible_fall" ? ClinicalTheme.red : ClinicalTheme.amber).frame(width: 7, height: 7); Text(incident.title.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption); Spacer(); Text("\(Int(incident.confidence * 100))%").font(.caption.monospacedDigit()).foregroundStyle(ClinicalTheme.muted) }
            }
        }.clinicalCard()
    }
}

// MARK: - MJPEG Loader / Video

final class MjpegLoader: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var image: UIImage?
    @Published var connected = false
    @Published var fps = 0.0
    private var task: URLSessionDataTask?
    private var session: URLSession!
    private var bytes = Data()
    private let boundary = "--medassistframe".data(using: .ascii)!
    private var frames = 0
    private var timer = Date()

    func start(_ url: URL) {
        stop()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        task = session.dataTask(with: url); task?.resume(); connected = true
    }
    func stop() { task?.cancel(); task = nil; bytes.removeAll(); connected = false }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { bytes.append(data); decode(); if bytes.count > 2_000_000 { bytes.removeAll() } }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { DispatchQueue.main.async { self.connected = false } }

    private func decode() {
        while let mark = bytes.range(of: boundary) {
            let rest = bytes[mark.upperBound...]
            guard let endHeader = rest.range(of: "\r\n\r\n".data(using: .ascii)!), let header = String(data: rest[..<endHeader.lowerBound], encoding: .ascii), let length = contentLength(header) else { return }
            let begin = endHeader.upperBound
            guard bytes.distance(from: begin, to: bytes.endIndex) >= length else { return }
            let end = bytes.index(begin, offsetBy: length)
            if let photo = UIImage(data: Data(bytes[begin..<end])) { DispatchQueue.main.async { self.image = photo; self.countFrame() } }
            bytes.removeSubrange(bytes.startIndex..<end)
        }
    }
    private func contentLength(_ header: String) -> Int? { header.split(separator: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }.flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } }
    private func countFrame() { frames += 1; let elapsed = Date().timeIntervalSince(timer); if elapsed > 1 { fps = Double(frames) / elapsed; frames = 0; timer = Date() } }
}

struct VideoCommandView: View {
    @EnvironmentObject var robot: RobotConnectionManager
    @StateObject private var stream = MjpegLoader()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    LinkStrip()
                    GeometryReader { geometry in
                        ZStack {
                            if let photo = stream.image { Image(uiImage: photo).resizable().aspectRatio(contentMode: .fit).overlay(AIDetectionOverlay(detections: robot.detections)) }
                            else { VStack(spacing: 12) { ProgressView().tint(ClinicalTheme.teal); Text("AWAITING CAMERA TELEMETRY").font(.caption.bold().monospaced()).foregroundStyle(ClinicalTheme.muted) } }
                            VStack { HStack { badge; Spacer(); snapshotButton }.padding(12); Spacer() }
                        }.frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }
            .navigationTitle("Clinical Observation")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if let url = robot.streamURL { stream.start(url) } }
            .onDisappear { stream.stop() }
        }
    }

    private var badge: some View { Text(stream.connected ? String(format: "LIVE  %.0f FPS", stream.fps) : "CAMERA OFFLINE").font(.caption2.bold().monospaced()).padding(.horizontal, 9).padding(.vertical, 5).background(.black.opacity(0.62), in: Capsule()).foregroundStyle(stream.connected ? ClinicalTheme.green : ClinicalTheme.amber) }
    private var snapshotButton: some View { Button { save() } label: { Image(systemName: "camera.fill").padding(10).background(.black.opacity(0.62), in: Circle()).foregroundStyle(.white) } }
    private func save() { guard let photo = stream.image else { return }; PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in guard status == .authorized || status == .limited else { return }; PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: photo) } } }
}

struct AIDetectionOverlay: View {
    let detections: [DetectedObject]
    var body: some View {
        GeometryReader { g in
            ForEach(detections) { d in
                let r = CGRect(x: d.x * g.size.width, y: d.y * g.size.height, width: d.w * g.size.width, height: d.h * g.size.height)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5).stroke(color(d.label), lineWidth: 2).frame(width: r.width, height: r.height)
                    Text("\(d.label.replacingOccurrences(of: "_", with: " ").uppercased())  \(Int(d.conf * 100))%").font(.caption2.bold()).padding(4).background(color(d.label)).foregroundStyle(.white).offset(y: -22)
                }.position(x: r.midX, y: r.midY)
            }
        }.allowsHitTesting(false)
    }
    private func color(_ label: String) -> Color {
        switch label {
        case "possible_fall": return ClinicalTheme.red
        case "red_flag_area": return ClinicalTheme.amber
        case "prolonged_immobility": return ClinicalTheme.red
        case "sustained_agitation": return ClinicalTheme.amber
        case "person": return ClinicalTheme.green
        default: return ClinicalTheme.teal
        }
    }
}

// MARK: - Manual Drive

struct ManualDriveView: View {
    @EnvironmentObject var robot: RobotConnectionManager
    @State private var speed = 160.0
    @State private var pan = 90.0
    @State private var tilt = 90.0

    var body: some View {
        NavigationStack {
            ZStack {
                ClinicalTheme.navy.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        LinkStrip()
                        if robot.autonomous { locked } else { controls }
                    }.padding(16)
                }
            }.navigationTitle("Precision Drive").navigationBarTitleDisplayMode(.inline)
        }
    }

    private var locked: some View {
        VStack(spacing: 12) { Image(systemName: "lock.shield.fill").font(.system(size: 42)).foregroundStyle(ClinicalTheme.amber); Text("UNMANNED MODE HOLDS CONTROL").font(.headline); Text("End autonomous patrol on the Unmanned tab before operating manually.").font(.caption).foregroundStyle(ClinicalTheme.muted).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).clinicalCard()
    }

    private var controls: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading) { Text("PROPULSION LIMIT  \(Int(speed)) / 255").font(.caption.bold().monospaced()).foregroundStyle(ClinicalTheme.muted); Slider(value: $speed, in: 60...255, step: 5).tint(ClinicalTheme.teal) }.clinicalCard()
            dpad.clinicalCard()
            Button(role: .destructive) { robot.stop() } label: { Label("EMERGENCY STOP", systemImage: "octagon.fill").frame(maxWidth: .infinity).padding(.vertical, 12) }.buttonStyle(.borderedProminent).tint(ClinicalTheme.red)
            cameraArm.clinicalCard()
        }
    }

    private var dpad: some View {
        VStack(spacing: 13) { driveButton(.forward, "chevron.up"); HStack(spacing: 52) { driveButton(.left, "chevron.left"); driveButton(.right, "chevron.right") }; driveButton(.reverse, "chevron.down") }
    }
    private func driveButton(_ d: DriveDirection, _ icon: String) -> some View { Image(systemName: icon).font(.title).foregroundStyle(ClinicalTheme.teal).frame(width: 68, height: 60).background(ClinicalTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14)).gesture(DragGesture(minimumDistance: 0).onChanged { _ in robot.drive(d, speed: Int(speed)) }.onEnded { _ in robot.stop() }) }
    private var cameraArm: some View { VStack(alignment: .leading, spacing: 12) { Text("CAMERA GIMBAL").font(.caption.bold().monospaced()).foregroundStyle(ClinicalTheme.muted); Text("PAN  \(Int(pan))°").font(.caption); Slider(value: $pan, in: 0...180, step: 1) { editing in if !editing { robot.setServo(1, Int(pan)) } }.tint(ClinicalTheme.teal); Text("TILT  \(Int(tilt))°").font(.caption); Slider(value: $tilt, in: 0...180, step: 1) { editing in if !editing { robot.setServo(2, Int(tilt)) } }.tint(ClinicalTheme.teal) } }
}

// MARK: - Unmanned Mode

struct UnmannedModeView: View {
    @EnvironmentObject var robot: RobotConnectionManager
    @State private var confirm = false
    @State private var guardEnabled = true
    @State private var reminder = 0.0

    var body: some View {
        NavigationStack {
            ZStack {
                ClinicalTheme.navy.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        LinkStrip(); autonomyStatus; action; Toggle("ULTRASONIC SAFETY GUARD", isOn: $guardEnabled).onChange(of: guardEnabled) { robot.setGuard($0) }.font(.caption.bold().monospaced()).clinicalCard(); reminderCard; rules
                    }.padding(16)
                }
            }
            .navigationTitle("Unmanned Operations").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Authorize Unmanned Patrol?", isPresented: $confirm, titleVisibility: .visible) {
                Button("AUTHORIZE AUTONOMOUS PATROL", role: .destructive) { robot.engageAutonomy() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("The robot will travel using its onboard line tracking and ultrasonic safety stop. Manual drive controls will lock until you end this mode.") }
        }
    }

    private var autonomyStatus: some View { VStack(spacing: 12) { Image(systemName: robot.autonomous ? "brain.head.profile.fill" : "brain.head.profile").font(.system(size: 52)).foregroundStyle(robot.autonomous ? ClinicalTheme.amber : ClinicalTheme.teal); Text(robot.autonomous ? "PATROL AUTHORIZED" : "AUTONOMY STANDBY").font(.headline.bold().monospaced()); Text(robot.autonomous ? "Onboard navigation and environmental safety monitoring are active." : "Operator authorization required before unattended navigation.").font(.caption).foregroundStyle(ClinicalTheme.muted).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).clinicalCard() }
    private var action: some View { Group { if robot.autonomous { Button { robot.endAutonomy() } label: { Label("END PATROL — RETURN TO MANUAL", systemImage: "hand.raised.fill").frame(maxWidth: .infinity).padding(.vertical, 12) }.buttonStyle(.borderedProminent).tint(ClinicalTheme.red) } else { Button { confirm = true } label: { Label("AUTHORIZE UNMANNED PATROL", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 12) }.buttonStyle(.borderedProminent).tint(ClinicalTheme.teal).disabled(!robot.isOnline) } } }
    private var reminderCard: some View { VStack(alignment: .leading) { Text(reminder == 0 ? "MEDICINE REMINDER: DISABLED" : "MEDICINE REMINDER: \(Int(reminder)) MINUTES").font(.caption.bold().monospaced()).foregroundStyle(ClinicalTheme.muted); Slider(value: $reminder, in: 0...180, step: 5) { editing in if !editing { robot.setReminder(Int(reminder)) } }.tint(ClinicalTheme.teal) }.clinicalCard() }
    private var rules: some View { VStack(alignment: .leading, spacing: 7) { Label("AUTONOMY SAFETY PROTOCOL", systemImage: "shield.lefthalf.filled").font(.caption.bold()); Text("• Obstacle cutoff: 12 cm\n• Lost communication: Uno watchdog halts drive\n• Chassis tip: audible alarm and telemetry alert\n• Manual drive remains locked until patrol is ended").font(.caption).foregroundStyle(ClinicalTheme.muted) }.clinicalCard() }
}

// MARK: - Patient Monitor (Vitals) — NEW

struct PatientMonitorView: View {
    @EnvironmentObject var robot: RobotConnectionManager

    var body: some View {
        NavigationStack {
            ZStack {
                ClinicalTheme.navy.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        LinkStrip()
                        disclaimerBanner
                        if let v = robot.vitals {
                            alertBanners(v)
                            presenceCard(v)
                            gaugeGrid(v)
                        } else {
                            Text("Waiting for AI vitals stream…").font(.caption).foregroundStyle(ClinicalTheme.muted).clinicalCard()
                        }
                    }.padding(16)
                }
            }
            .navigationTitle("Patient Monitor").navigationBarTitleDisplayMode(.inline)
        }
    }

    private var disclaimerBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(ClinicalTheme.teal)
            Text("Camera-based visual AI cues to guide a caregiver's attention. These are NOT a medical diagnosis — always verify the patient in person.")
                .font(.caption2).foregroundStyle(ClinicalTheme.muted)
        }.clinicalCard()
    }

    private func alertBanners(_ v: VitalsFrame) -> some View {
        VStack(spacing: 10) {
            if v.immobility_alert {
                alertBanner(icon: "figure.fall", text: "Prolonged stillness detected — please check on patient", color: ClinicalTheme.red)
            }
            if v.agitation_alert {
                alertBanner(icon: "waveform.path", text: "Sustained high motion detected — possible distress or restlessness", color: ClinicalTheme.amber)
            }
        }
    }

    private func alertBanner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.white)
            Text(text).font(.caption.bold()).foregroundStyle(.white)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(color, in: RoundedRectangle(cornerRadius: 14))
    }

    private func presenceCard(_ v: VitalsFrame) -> some View {
        HStack(spacing: 14) {
            Image(systemName: v.person_present ? "person.fill.checkmark" : "person.fill.questionmark")
                .font(.title).foregroundStyle(v.person_present ? ClinicalTheme.green : ClinicalTheme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(v.person_present ? "PATIENT IN FRAME" : "NO PERSON DETECTED").font(.subheadline.bold().monospaced())
                Text(v.person_present ? "Continuous visual monitoring active" : "Point camera toward patient area").font(.caption2).foregroundStyle(ClinicalTheme.muted)
            }
            Spacer()
        }.clinicalCard()
    }

    private func gaugeGrid(_ v: VitalsFrame) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            vitalGauge("figure.walk.motion", "MOTION", v.motion_score, ClinicalTheme.teal)
            vitalGauge("bed.double.fill", "STILLNESS", min(1.0, v.immobility_sec / 90.0), v.immobility_alert ? ClinicalTheme.red : ClinicalTheme.teal, suffix: "\(Int(v.immobility_sec))s")
            vitalGauge("drop.fill", "PALLOR CUE", v.pallor_score, ClinicalTheme.amber)
            vitalGauge("wind", "CYANOSIS CUE", v.cyanosis_score, ClinicalTheme.red)
        }
    }

    private func vitalGauge(_ icon: String, _ label: String, _ value: Double, _ color: Color, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Spacer()
                Text(suffix ?? "\(Int(value * 100))%").font(.caption.bold().monospacedDigit())
            }
            ProgressView(value: value).tint(color)
            Text(label).font(.caption2.bold().monospaced()).foregroundStyle(ClinicalTheme.muted)
        }.clinicalCard()
    }
}

// MARK: - Systems / Diagnostics

struct SystemsView: View {
    @EnvironmentObject var robot: RobotConnectionManager
    @State private var editHost = false

    var body: some View {
        NavigationStack {
            ZStack {
                ClinicalTheme.navy.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        LinkStrip(); telemetry; setupDiagnostics; incidentHistory; connectionCard
                    }.padding(16)
                }
            }.navigationTitle("Systems & Diagnostics").navigationBarTitleDisplayMode(.inline)
        }
    }

    private var telemetry: some View { Group { if let t = robot.telemetry { VStack(alignment: .leading, spacing: 10) { Label("MOTION TELEMETRY", systemImage: "waveform.path.ecg").font(.caption.bold().monospaced()).foregroundStyle(ClinicalTheme.teal); grid("DISTANCE", t.hasDistance ? String(format: "%.1f cm", t.US) : "NO ECHO", "BATTERY", t.BATT.map { String(format: "%.2f V", $0) } ?? "—"); grid("MODE", t.isAutonomous ? "PATROL" : "MANUAL", "LINE L/M/R", t.LT.map(String.init).joined(separator: " / ")); Divider(); Text(String(format: "ACCEL   %.2f / %.2f / %.2f g", t.GY.ax, t.GY.ay, t.GY.az)).font(.caption2.monospacedDigit()); Text(String(format: "GYRO    %.1f / %.1f / %.1f °/s", t.GY.gx, t.GY.gy, t.GY.gz)).font(.caption2.monospacedDigit()) }.clinicalCard() } else { Text("Waiting for Arduino Uno sensor telemetry…").font(.caption).foregroundStyle(ClinicalTheme.muted).clinicalCard() } } }
    private func grid(_ a: String, _ av: String, _ b: String, _ bv: String) -> some View { HStack { value(a, av); Spacer(); value(b, bv) } }
    private func value(_ label: String, _ text: String) -> some View { VStack(alignment: .leading) { Text(label).font(.caption2.bold().monospaced()).foregroundStyle(ClinicalTheme.muted); Text(text).font(.subheadline.bold().monospacedDigit()) } }
    private var setupDiagnostics: some View { VStack(alignment: .leading, spacing: 9) { Label("ESP32 DIAGNOSTICS", systemImage: "cpu").font(.caption.bold().monospaced()).foregroundStyle(ClinicalTheme.teal); if let h = robot.health { diag("Setup network", h.ap_ssid); diag("Robot address", h.ap_ip); diag("Camera", h.camera_ok ? "ONLINE" : "UNAVAILABLE"); diag("PSRAM", h.psram ? "DETECTED" : "NOT DETECTED"); diag("AP clients", "\(h.ap_clients)"); diag("Free memory", "\(h.free_heap / 1024) KB") } else { Text("No /health response yet. Join MedAssist-Robot, then tap Retry.").font(.caption).foregroundStyle(ClinicalTheme.muted) } }.clinicalCard() }
    private func diag(_ label: String, _ value: String) -> some View { HStack { Text(label).font(.caption).foregroundStyle(ClinicalTheme.muted); Spacer(); Text(value).font(.caption.bold().monospaced()) } }
    private var incidentHistory: some View { VStack(alignment: .leading, spacing: 8) { Label("INCIDENT HISTORY", systemImage: "clock.arrow.circlepath").font(.caption.bold().monospaced()).foregroundStyle(ClinicalTheme.teal); if robot.incidents.isEmpty { Text("No vision incidents logged.").font(.caption).foregroundStyle(ClinicalTheme.muted) }; ForEach(robot.incidents.prefix(12)) { event in HStack { Text(event.title.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption); Spacer(); Text("\(Int(event.confidence * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(ClinicalTheme.muted); Text(event.date.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(ClinicalTheme.muted) } } }.clinicalCard() }
    private var connectionCard: some View { VStack(alignment: .leading, spacing: 10) { Label("NETWORK", systemImage: "wifi").font(.caption.bold().monospaced()).foregroundStyle(ClinicalTheme.teal); HStack { Text(robot.robotHost).font(.caption.monospaced()); Spacer(); Button("EDIT") { editHost = true }.font(.caption.bold()) }; Button { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } label: { Label("OPEN IPHONE WI-FI SETTINGS", systemImage: "wifi").frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.bordered).tint(ClinicalTheme.teal) }.clinicalCard().sheet(isPresented: $editHost) { AddressEditor() } }
}

struct AddressEditor: View {
    @EnvironmentObject var robot: RobotConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    var body: some View { NavigationStack { Form { Section("Robot Address") { TextField("192.168.4.1", text: $address).textInputAutocapitalization(.never); Text("Default: join MedAssist-Robot Wi-Fi, use 192.168.4.1.").font(.caption) }; Section { Button("SAVE AND CONNECT") { robot.robotHost = address; robot.disconnect(); robot.connect(); dismiss() } } }.navigationTitle("Network Link").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }.onAppear { address = robot.robotHost } } }
}
