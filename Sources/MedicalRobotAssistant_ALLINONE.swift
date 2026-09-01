//
//  MedAssist_iOS_FINAL.swift
//  MedAssist Hospital Command — FINAL professional build.
//
//  Built to match the confirmed working ESP32 stream/bridge protocol:
//    MJPEG URL:  http://192.168.4.1/stream
//    Boundary:   --medassistframe
//    WebSocket:  ws://192.168.4.1/ws
//    Health:     http://192.168.4.1/health
//
//  iOS 16+ | one source file | no image asset catalog required.
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

// MARK: - Branded Launch Screen

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
            LinearGradient(
                colors: [ClinicalTheme.navy, Color(red: 0.02, green: 0.03, blue: 0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                MedAssistLogo()
                    .scaleEffect(pulse ? 1.05 : 0.92)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)

                VStack(spacing: 4) {
                    Text("MEDASSIST")
                        .font(.title2.bold().monospaced())
                        .foregroundStyle(.white)
                    Text("HOSPITAL ROBOTICS COMMAND")
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(ClinicalTheme.teal)
                }

                ProgressView()
                    .tint(ClinicalTheme.teal)
                    .padding(.top, 6)
            }
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Clinical Theme

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
                .fill(
                    LinearGradient(
                        colors: [ClinicalTheme.teal, Color(red: 0, green: 0.45, blue: 0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
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
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.075), lineWidth: 1)
            )
    }
}

extension View {
    func clinicalCard(_ padding: CGFloat = 16) -> some View {
        modifier(ClinicalCard(padding: padding))
    }
}

// MARK: - Wire Protocol Models

struct GyroReading: Codable {
    let ax: Double
    let ay: Double
    let az: Double
    let gx: Double
    let gy: Double
    let gz: Double
}

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
    let conf: Double
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    enum CodingKeys: String, CodingKey {
        case label, conf, x, y, w, h
    }
}

struct DetectionFrame: Codable {
    let TYPE: String
    let T: Int
    let objects: [DetectedObject]
}

struct Heartbeat: Codable {
    let TYPE: String
    let uptime_s: Int
    let rssi: Int
    let clients: Int
    let camera: Bool?
}

struct BridgeStatus: Codable {
    let TYPE: String
    let uno_rx_bytes: Int
    let uno_tx_bytes: Int
    let ws_commands: Int
    let camera_ok: Bool
    let camera_note: String?
}

struct HealthStatus: Codable {
    let status: String
    let platform: String?
    let ap_ssid: String
    let ap_ip: String
    let ap_clients: Int
    let camera_ok: Bool
    let psram: Bool
    let free_heap: Int
    let uptime_s: Int
    let sta_connected: Bool?
    let sta_ip: String?
    let uno_rx_bytes: Int?
    let uno_tx_bytes: Int?
    let ws_commands: Int?
    let uart_rx_pin: Int?
    let uart_tx_pin: Int?
}

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

struct RobotCommand: Codable {
    var H: Int
    var N: Int
    var D1: Int?
    var D2: Int?
    var D3: Int?
}

enum DriveDirection: Int {
    case left = 1
    case right = 2
    case forward = 3
    case reverse = 4
}

enum Commands {
    private static var sequence = 100

    private static func id() -> Int {
        sequence += 1
        return sequence
    }

    static func drive(_ direction: DriveDirection, speed: Int) -> RobotCommand {
        RobotCommand(H: id(), N: 3, D1: direction.rawValue, D2: speed, D3: nil)
    }

    static func servo(_ servoID: Int, _ degrees: Int) -> RobotCommand {
        RobotCommand(H: id(), N: 5, D1: servoID, D2: degrees, D3: nil)
    }

    static func stop() -> RobotCommand {
        RobotCommand(H: id(), N: 100, D1: nil, D2: nil, D3: nil)
    }

    static func autonomous(_ enabled: Bool) -> RobotCommand {
        RobotCommand(H: id(), N: 101, D1: enabled ? 1 : 0, D2: nil, D3: nil)
    }

    static func guardEnabled(_ enabled: Bool) -> RobotCommand {
        RobotCommand(H: id(), N: 900, D1: enabled ? 1 : 0, D2: nil, D3: nil)
    }

    static func reminder(_ minutes: Int) -> RobotCommand {
        RobotCommand(H: id(), N: 901, D1: minutes, D2: nil, D3: nil)
    }

    static func buzzer() -> RobotCommand {
        RobotCommand(H: id(), N: 902, D1: 2, D2: nil, D3: nil)
    }
}

enum ConnectionPhase: Equatable {
    case offline
    case connecting
    case online
    case warning
    case unavailable(String)

    var title: String {
        switch self {
        case .offline: return "OFFLINE"
        case .connecting: return "CONNECTING"
        case .online: return "LIVE"
        case .warning: return "DEGRADED"
        case .unavailable: return "UNREACHABLE"
        }
    }

    var color: Color {
        switch self {
        case .offline: return .gray
        case .connecting, .warning: return ClinicalTheme.amber
        case .online: return ClinicalTheme.green
        case .unavailable: return ClinicalTheme.red
        }
    }
}

// MARK: - Robot Connection Manager

@MainActor
final class RobotConnectionManager: NSObject, ObservableObject {
    @Published var phase: ConnectionPhase = .offline
    @Published var robotHost = "192.168.4.1"
    @Published var telemetry: RobotTelemetry?
    @Published var detections: [DetectedObject] = []
    @Published var incidents: [Incident] = []
    @Published var heartbeat: Heartbeat?
    @Published var bridge: BridgeStatus?
    @Published var health: HealthStatus?
    @Published var vitals: VitalsFrame?
    @Published var autonomous = false
    @Published var lastMessageAt: Date?

    var isOnline: Bool {
        phase == .online || phase == .warning
    }

    var streamURL: URL? {
        URL(string: "http://\(robotHost)/stream")
    }

    var healthURL: URL? {
        URL(string: "http://\(robotHost)/health")
    }

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
        guard let url = URL(string: "ws://\(robotHost)/ws") else {
            phase = .unavailable("Bad address")
            return
        }

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
                    let text: String?
                    switch message {
                    case .string(let value): text = value
                    case .data(let data): text = String(data: data, encoding: .utf8)
                    @unknown default: text = nil
                    }
                    if let text {
                        self.consume(text)
                    }
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
            if let value = try? decoder.decode(Heartbeat.self, from: data) {
                heartbeat = value
                phase = .online
                retrySeconds = 1
            }
        } else if text.contains("\"TYPE\":\"bridge\"") || text.contains("\"TYPE\": \"bridge\"") {
            if let value = try? decoder.decode(BridgeStatus.self, from: data) {
                bridge = value
                phase = .online
                retrySeconds = 1
            }
        } else if text.contains("\"TYPE\":\"detections\"") || text.contains("\"TYPE\": \"detections\"") {
            if let value = try? decoder.decode(DetectionFrame.self, from: data) {
                detections = value.objects
                for object in value.objects {
                    incidents.insert(
                        Incident(date: Date(), title: object.label, confidence: object.conf),
                        at: 0
                    )
                    if object.label == "possible_fall" {
                        haptics.notificationOccurred(.warning)
                    }
                }
                if incidents.count > 60 {
                    incidents.removeLast(incidents.count - 60)
                }
                clearStaleDetections()
            }
        } else if text.contains("\"TYPE\":\"vitals\"") || text.contains("\"TYPE\": \"vitals\"") {
            if let value = try? decoder.decode(VitalsFrame.self, from: data) {
                let previousAlert = vitals?.immobility_alert ?? false
                vitals = value
                if value.immobility_alert && !previousAlert {
                    haptics.notificationOccurred(.warning)
                }
            }
        } else if text.contains("\"US\"") {
            if let value = try? decoder.decode(RobotTelemetry.self, from: data) {
                let previouslyTipped = telemetry?.isTipped ?? false
                telemetry = value
                autonomous = value.isAutonomous
                if value.isTipped && !previouslyTipped {
                    haptics.notificationOccurred(.error)
                }
            }
        }
    }

    private func beginMonitoring() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    private func evaluate() {
        pollHealth()
        guard let lastMessageAt else { return }
        if Date().timeIntervalSince(lastMessageAt) > 7 && socket?.state == .running {
            phase = .warning
        }
    }

    func pollHealth() {
        guard let url = healthURL else { return }
        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let value = try? JSONDecoder().decode(HealthStatus.self, from: data) else { return }
            Task { @MainActor in self?.health = value }
        }
        .resume()
    }

    private func retry() {
        guard !intentionalDisconnect else { return }
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: retrySeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.connect() }
        }
        retrySeconds = min(retrySeconds * 2, 12)
    }

    private func clearStaleDetections() {
        detectionTimer?.invalidate()
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.detections = [] }
        }
    }

    private func networkError(_ error: Error) -> String {
        let code = (error as NSError).code
        if code == -1004 { return "Robot not found" }
        if code == -1001 { return "Timed out" }
        return "Link interrupted"
    }

    func send(_ command: RobotCommand) {
        guard let data = try? JSONEncoder().encode(command),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { _ in }
    }

    func drive(_ direction: DriveDirection, speed: Int) {
        send(Commands.drive(direction, speed: speed))
    }

    func stop() {
        send(Commands.stop())
    }

    func setServo(_ id: Int, _ degrees: Int) {
        send(Commands.servo(id, degrees))
    }

    func setGuard(_ enabled: Bool) {
        send(Commands.guardEnabled(enabled))
    }

    func setReminder(_ minutes: Int) {
        send(Commands.reminder(minutes))
    }

    func buzz() {
        send(Commands.buzzer())
    }

    func engageAutonomy() {
        autonomous = true
        send(Commands.autonomous(true))
    }

    func endAutonomy() {
        autonomous = false
        stop()
        send(Commands.autonomous(false))
    }
}

// MARK: - Navigation

struct CommandCenterView: View {
    var body: some View {
        TabView {
            MissionDashboard()
                .tabItem { Label("Mission", systemImage: "cross.case.fill") }
            VideoCommandView()
                .tabItem { Label("Observe", systemImage: "video.fill") }
            ManualDriveView()
                .tabItem { Label("Drive", systemImage: "steeringwheel") }
            UnmannedModeView()
                .tabItem { Label("Unmanned", systemImage: "brain.head.profile") }
            PatientMonitorView()
                .tabItem { Label("Vitals", systemImage: "waveform.path.ecg") }
            SystemsView()
                .tabItem { Label("Systems", systemImage: "gearshape.fill") }
        }
    }
}

struct LinkStrip: View {
    @EnvironmentObject var robot: RobotConnectionManager

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(robot.phase.color)
                .frame(width: 8, height: 8)
            Text(robot.phase.title)
                .font(.caption2.bold().monospaced())
            Spacer()
            Text(robot.robotHost)
                .font(.caption2.monospaced())
                .foregroundStyle(ClinicalTheme.muted)
            if robot.phase != .online {
                Button("RETRY") { robot.connect() }
                    .font(.caption2.bold())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
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
                        bridgePanel
                        responseRow
                        incidentPanel
                    }
                    .padding(16)
                }
            }
            .navigationTitle("MedAssist Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MedAssistLogo(compact: true)
                }
            }
            .onAppear {
                if !robot.isOnline { robot.connect() }
            }
        }
    }

    private var missionHeader: some View {
        HStack(spacing: 14) {
            MedAssistLogo()
            VStack(alignment: .leading, spacing: 4) {
                Text("UNIT MA-01")
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(ClinicalTheme.teal)
                Text(robot.autonomous ? "UNMANNED CARE PATROL" : "CLINICAL SUPPORT READY")
                    .font(.headline)
                Text(robot.autonomous ? "Autonomous sensor-guided navigation active" : "Secure manual operator control available")
                    .font(.caption)
                    .foregroundStyle(ClinicalTheme.muted)
            }
            Spacer()
        }
        .clinicalCard()
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metric("battery.75", "POWER", robot.telemetry?.BATT.map { String(format: "%.1f V", $0) } ?? "—", color: batteryColor)
            metric("ruler", "CLEARANCE", robot.telemetry?.hasDistance == true ? String(format: "%.0f cm", robot.telemetry!.US) : "—", color: ClinicalTheme.teal)
            metric("wifi", "LINK", robot.heartbeat.map { "\($0.rssi) dBm" } ?? "—", color: ClinicalTheme.teal)
            metric(robot.telemetry?.isTipped == true ? "exclamationmark.triangle.fill" : "checkmark.shield.fill", "SAFETY", robot.telemetry?.isTipped == true ? "ALERT" : "NOMINAL", color: robot.telemetry?.isTipped == true ? ClinicalTheme.red : ClinicalTheme.green)
        }
    }

    private var batteryColor: Color {
        (robot.telemetry?.BATT ?? 8) < 6.6 ? ClinicalTheme.red : ClinicalTheme.green
    }

    private func metric(_ icon: String, _ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption2.bold().monospaced())
                .foregroundStyle(ClinicalTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clinicalCard()
    }

    private var bridgePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("UNO BRIDGE", systemImage: "cable.connector")
                .font(.caption.bold().monospaced())
                .foregroundStyle(ClinicalTheme.teal)
            if let bridge = robot.bridge {
                HStack {
                    Text("Telemetry RX: \(bridge.uno_rx_bytes) B")
                    Spacer()
                    Text("Commands TX: \(bridge.uno_tx_bytes) B")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(ClinicalTheme.muted)
                Text(bridge.uno_rx_bytes > 0 ? "Uno telemetry link active" : "No Uno data yet — check S1 CAM and UART wiring")
                    .font(.caption2)
                    .foregroundStyle(bridge.uno_rx_bytes > 0 ? ClinicalTheme.green : ClinicalTheme.amber)
            } else {
                Text("Waiting for ESP32 bridge status…")
                    .font(.caption)
                    .foregroundStyle(ClinicalTheme.muted)
            }
        }
        .clinicalCard()
    }

    private var responseRow: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                robot.stop()
            } label: {
                Label("E-STOP", systemImage: "octagon.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(ClinicalTheme.red)

            Button {
                robot.buzz()
            } label: {
                Label("CALL", systemImage: "bell.badge.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(ClinicalTheme.teal)
        }
    }

    private var incidentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AI INCIDENT QUEUE", systemImage: "eye.trianglebadge.exclamationmark")
                    .font(.caption.bold())
                Spacer()
                Text("\(robot.incidents.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ClinicalTheme.muted)
            }
            if robot.incidents.isEmpty {
                Text("No clinical visual events recorded.")
                    .font(.caption)
                    .foregroundStyle(ClinicalTheme.muted)
            }
            ForEach(robot.incidents.prefix(3)) { incident in
                HStack {
                    Circle()
                        .fill(incident.title == "possible_fall" ? ClinicalTheme.red : ClinicalTheme.amber)
                        .frame(width: 7, height: 7)
                    Text(incident.title.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                    Spacer()
                    Text("\(Int(incident.confidence * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ClinicalTheme.muted)
                }
            }
        }
        .clinicalCard()
    }
}

// MARK: - MJPEG Loader

final class MjpegLoader: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var image: UIImage?
    @Published var connected = false
    @Published var fps = 0.0
    @Published var lastError = ""

    private var task: URLSessionDataTask?
    private var session: URLSession!
    private var bytes = Data()

    // This must match ESP32 stream boundary exactly: --medassistframe
    private let boundary = "--medassistframe".data(using: .ascii)!
    private var frames = 0
    private var timer = Date()

    func start(_ url: URL) {
        stop()
        lastError = ""
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        task = session.dataTask(with: url)
        task?.resume()
        connected = true
    }

    func stop() {
        task?.cancel()
        task = nil
        bytes.removeAll()
        connected = false
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        bytes.append(data)
        decode()
        if bytes.count > 2_000_000 {
            bytes.removeAll()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            self.connected = false
            if let error {
                self.lastError = error.localizedDescription
            }
        }
    }

    private func decode() {
        while let mark = bytes.range(of: boundary) {
            let rest = bytes[mark.upperBound...]
            guard let headerEnd = rest.range(of: "\r\n\r\n".data(using: .ascii)!),
                  let header = String(data: rest[..<headerEnd.lowerBound], encoding: .ascii),
                  let length = contentLength(header) else {
                return
            }

            let jpegStart = headerEnd.upperBound
            guard bytes.distance(from: jpegStart, to: bytes.endIndex) >= length else {
                return
            }
            let jpegEnd = bytes.index(jpegStart, offsetBy: length)

            if let photo = UIImage(data: Data(bytes[jpegStart..<jpegEnd])) {
                DispatchQueue.main.async {
                    self.image = photo
                    self.countFrame()
                }
            }
            bytes.removeSubrange(bytes.startIndex..<jpegEnd)
        }
    }

    private func contentLength(_ header: String) -> Int? {
        header.split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap {
                Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces))
            }
    }

    private func countFrame() {
        frames += 1
        let elapsed = Date().timeIntervalSince(timer)
        if elapsed > 1 {
            fps = Double(frames) / elapsed
            frames = 0
            timer = Date()
        }
    }
}

// MARK: - Observation

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
                            if let photo = stream.image {
                                Image(uiImage: photo)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .overlay(AIDetectionOverlay(detections: robot.detections))
                            } else {
                                VStack(spacing: 12) {
                                    ProgressView().tint(ClinicalTheme.teal)
                                    Text(stream.lastError.isEmpty ? "AWAITING CAMERA TELEMETRY" : stream.lastError)
                                        .font(.caption.bold().monospaced())
                                        .foregroundStyle(ClinicalTheme.muted)
                                    Text("If this persists, open /snapshot in Safari to verify the camera.")
                                        .font(.caption2)
                                        .foregroundStyle(ClinicalTheme.muted)
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                            }

                            VStack {
                                HStack {
                                    badge
                                    Spacer()
                                    snapshotButton
                                }
                                .padding(12)
                                Spacer()
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }
            .navigationTitle("Clinical Observation")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let url = robot.streamURL {
                    stream.start(url)
                }
            }
            .onDisappear { stream.stop() }
            .onChange(of: robot.robotHost) { _ in
                if let url = robot.streamURL {
                    stream.start(url)
                }
            }
        }
    }

    private var badge: some View {
        Text(stream.connected ? String(format: "LIVE  %.0f FPS", stream.fps) : "CAMERA OFFLINE")
            .font(.caption2.bold().monospaced())
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black.opacity(0.62), in: Capsule())
            .foregroundStyle(stream.connected ? ClinicalTheme.green : ClinicalTheme.amber)
    }

    private var snapshotButton: some View {
        Button { save() } label: {
            Image(systemName: "camera.fill")
                .padding(10)
                .background(.black.opacity(0.62), in: Circle())
                .foregroundStyle(.white)
        }
    }

    private func save() {
        guard let photo = stream.image else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: photo)
            }
        }
    }
}

struct AIDetectionOverlay: View {
    let detections: [DetectedObject]

    var body: some View {
        GeometryReader { geometry in
            ForEach(detections) { detection in
                let rect = CGRect(
                    x: detection.x * geometry.size.width,
                    y: detection.y * geometry.size.height,
                    width: detection.w * geometry.size.width,
                    height: detection.h * geometry.size.height
                )

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(color(detection.label), lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                    Text("\(detection.label.replacingOccurrences(of: "_", with: " ").uppercased())  \(Int(detection.conf * 100))%")
                        .font(.caption2.bold())
                        .padding(4)
                        .background(color(detection.label))
                        .foregroundStyle(.white)
                        .offset(y: -22)
                }
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }

    private func color(_ label: String) -> Color {
        switch label {
        case "possible_fall", "prolonged_immobility": return ClinicalTheme.red
        case "red_flag_area", "sustained_agitation": return ClinicalTheme.amber
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
                        if robot.autonomous {
                            locked
                        } else {
                            controls
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Precision Drive")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var locked: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 42))
                .foregroundStyle(ClinicalTheme.amber)
            Text("UNMANNED MODE HOLDS CONTROL")
                .font(.headline)
            Text("End autonomous patrol on the Unmanned tab before operating manually.")
                .font(.caption)
                .foregroundStyle(ClinicalTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .clinicalCard()
    }

    private var controls: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading) {
                Text("PROPULSION LIMIT  \(Int(speed)) / 255")
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(ClinicalTheme.muted)
                Slider(value: $speed, in: 60...255, step: 5)
                    .tint(ClinicalTheme.teal)
            }
            .clinicalCard()

            dpad.clinicalCard()

            Button(role: .destructive) {
                robot.stop()
            } label: {
                Label("EMERGENCY STOP", systemImage: "octagon.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(ClinicalTheme.red)

            cameraArm.clinicalCard()
        }
    }

    private var dpad: some View {
        VStack(spacing: 13) {
            driveButton(.forward, "chevron.up")
            HStack(spacing: 52) {
                driveButton(.left, "chevron.left")
                driveButton(.right, "chevron.right")
            }
            driveButton(.reverse, "chevron.down")
        }
    }

    private func driveButton(_ direction: DriveDirection, _ icon: String) -> some View {
        Image(systemName: icon)
            .font(.title)
            .foregroundStyle(ClinicalTheme.teal)
            .frame(width: 68, height: 60)
            .background(ClinicalTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in robot.drive(direction, speed: Int(speed)) }
                    .onEnded { _ in robot.stop() }
            )
    }

    private var cameraArm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CAMERA GIMBAL")
                .font(.caption.bold().monospaced())
                .foregroundStyle(ClinicalTheme.muted)
            Text("PAN  \(Int(pan))°")
                .font(.caption)
            Slider(value: $pan, in: 0...180, step: 1) { editing in
                if !editing { robot.setServo(1, Int(pan)) }
            }
            .tint(ClinicalTheme.teal)

            Text("TILT  \(Int(tilt))°")
                .font(.caption)
            Slider(value: $tilt, in: 0...180, step: 1) { editing in
                if !editing { robot.setServo(2, Int(tilt)) }
            }
            .tint(ClinicalTheme.teal)
        }
    }
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
                        LinkStrip()
                        autonomyStatus
                        action
                        Toggle("ULTRASONIC SAFETY GUARD", isOn: $guardEnabled)
                            .onChange(of: guardEnabled) { robot.setGuard($0) }
                            .font(.caption.bold().monospaced())
                            .clinicalCard()
                        reminderCard
                        rules
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Unmanned Operations")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Authorize Unmanned Patrol?", isPresented: $confirm, titleVisibility: .visible) {
                Button("AUTHORIZE AUTONOMOUS PATROL", role: .destructive) {
                    robot.engageAutonomy()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The robot will travel using its onboard line tracking and ultrasonic safety stop. Manual drive controls will lock until you end this mode.")
            }
        }
    }

    private var autonomyStatus: some View {
        VStack(spacing: 12) {
            Image(systemName: robot.autonomous ? "brain.head.profile.fill" : "brain.head.profile")
                .font(.system(size: 52))
                .foregroundStyle(robot.autonomous ? ClinicalTheme.amber : ClinicalTheme.teal)
            Text(robot.autonomous ? "PATROL AUTHORIZED" : "AUTONOMY STANDBY")
                .font(.headline.bold().monospaced())
            Text(robot.autonomous ? "Onboard navigation and environmental safety monitoring are active." : "Operator authorization required before unattended navigation.")
                .font(.caption)
                .foregroundStyle(ClinicalTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .clinicalCard()
    }

    private var action: some View {
        Group {
            if robot.autonomous {
                Button { robot.endAutonomy() } label: {
                    Label("END PATROL — RETURN TO MANUAL", systemImage: "hand.raised.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(ClinicalTheme.red)
            } else {
                Button { confirm = true } label: {
                    Label("AUTHORIZE UNMANNED PATROL", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(ClinicalTheme.teal)
                .disabled(!robot.isOnline)
            }
        }
    }

    private var reminderCard: some View {
        VStack(alignment: .leading) {
            Text(reminder == 0 ? "MEDICINE REMINDER: DISABLED" : "MEDICINE REMINDER: \(Int(reminder)) MINUTES")
                .font(.caption.bold().monospaced())
                .foregroundStyle(ClinicalTheme.muted)
            Slider(value: $reminder, in: 0...180, step: 5) { editing in
                if !editing { robot.setReminder(Int(reminder)) }
            }
            .tint(ClinicalTheme.teal)
        }
        .clinicalCard()
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("AUTONOMY SAFETY PROTOCOL", systemImage: "shield.lefthalf.filled")
                .font(.caption.bold())
            Text("• Obstacle cutoff: 12 cm\n• Lost communication: Uno watchdog halts drive\n• Chassis tip: audible alarm and telemetry alert\n• Manual drive remains locked until patrol is ended")
                .font(.caption)
                .foregroundStyle(ClinicalTheme.muted)
        }
        .clinicalCard()
    }
}

// MARK: - Patient Monitor

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
                        if let vitals = robot.vitals {
                            alertBanners(vitals)
                            presenceCard(vitals)
                            gaugeGrid(vitals)
                        } else {
                            Text("Waiting for AI vitals stream…")
                                .font(.caption)
                                .foregroundStyle(ClinicalTheme.muted)
                                .clinicalCard()
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Patient Monitor")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var disclaimerBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(ClinicalTheme.teal)
            Text("Camera-based visual AI cues to guide a caregiver's attention. These are NOT a medical diagnosis — always verify the patient in person.")
                .font(.caption2)
                .foregroundStyle(ClinicalTheme.muted)
        }
        .clinicalCard()
    }

    private func alertBanners(_ vitals: VitalsFrame) -> some View {
        VStack(spacing: 10) {
            if vitals.immobility_alert {
                alertBanner(icon: "figure.fall", text: "Prolonged stillness detected — please check on patient", color: ClinicalTheme.red)
            }
            if vitals.agitation_alert {
                alertBanner(icon: "waveform.path", text: "Sustained high motion detected — possible distress or restlessness", color: ClinicalTheme.amber)
            }
        }
    }

    private func alertBanner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.white)
            Text(text).font(.caption.bold()).foregroundStyle(.white)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color, in: RoundedRectangle(cornerRadius: 14))
    }

    private func presenceCard(_ vitals: VitalsFrame) -> some View {
        HStack(spacing: 14) {
            Image(systemName: vitals.person_present ? "person.fill.checkmark" : "person.fill.questionmark")
                .font(.title)
                .foregroundStyle(vitals.person_present ? ClinicalTheme.green : ClinicalTheme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(vitals.person_present ? "PATIENT IN FRAME" : "NO PERSON DETECTED")
                    .font(.subheadline.bold().monospaced())
                Text(vitals.person_present ? "Continuous visual monitoring active" : "Point camera toward patient area")
                    .font(.caption2)
                    .foregroundStyle(ClinicalTheme.muted)
            }
            Spacer()
        }
        .clinicalCard()
    }

    private func gaugeGrid(_ vitals: VitalsFrame) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            vitalGauge("figure.walk.motion", "MOTION", vitals.motion_score, ClinicalTheme.teal)
            vitalGauge("bed.double.fill", "STILLNESS", min(1.0, vitals.immobility_sec / 90.0), vitals.immobility_alert ? ClinicalTheme.red : ClinicalTheme.teal, suffix: "\(Int(vitals.immobility_sec))s")
            vitalGauge("drop.fill", "PALLOR CUE", vitals.pallor_score, ClinicalTheme.amber)
            vitalGauge("wind", "CYANOSIS CUE", vitals.cyanosis_score, ClinicalTheme.red)
        }
    }

    private func vitalGauge(_ icon: String, _ label: String, _ value: Double, _ color: Color, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Spacer()
                Text(suffix ?? "\(Int(value * 100))%")
                    .font(.caption.bold().monospacedDigit())
            }
            ProgressView(value: value)
                .tint(color)
            Text(label)
                .font(.caption2.bold().monospaced())
                .foregroundStyle(ClinicalTheme.muted)
        }
        .clinicalCard()
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
                        LinkStrip()
                        telemetry
                        bridgeDiagnostics
                        setupDiagnostics
                        incidentHistory
                        connectionCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Systems & Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var telemetry: some View {
        Group {
            if let telemetry = robot.telemetry {
                VStack(alignment: .leading, spacing: 10) {
                    Label("MOTION TELEMETRY", systemImage: "waveform.path.ecg")
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(ClinicalTheme.teal)
                    grid("DISTANCE", telemetry.hasDistance ? String(format: "%.1f cm", telemetry.US) : "NO ECHO", "BATTERY", telemetry.BATT.map { String(format: "%.2f V", $0) } ?? "—")
                    grid("MODE", telemetry.isAutonomous ? "PATROL" : "MANUAL", "LINE L/M/R", telemetry.LT.map(String.init).joined(separator: " / "))
                    Divider()
                    Text(String(format: "ACCEL   %.2f / %.2f / %.2f g", telemetry.GY.ax, telemetry.GY.ay, telemetry.GY.az))
                        .font(.caption2.monospacedDigit())
                    Text(String(format: "GYRO    %.1f / %.1f / %.1f °/s", telemetry.GY.gx, telemetry.GY.gy, telemetry.GY.gz))
                        .font(.caption2.monospacedDigit())
                }
                .clinicalCard()
            } else {
                Text("Waiting for Arduino Uno sensor telemetry…")
                    .font(.caption)
                    .foregroundStyle(ClinicalTheme.muted)
                    .clinicalCard()
            }
        }
    }

    private func grid(_ firstLabel: String, _ firstValue: String, _ secondLabel: String, _ secondValue: String) -> some View {
        HStack {
            value(firstLabel, firstValue)
            Spacer()
            value(secondLabel, secondValue)
        }
    }

    private func value(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption2.bold().monospaced())
                .foregroundStyle(ClinicalTheme.muted)
            Text(text)
                .font(.subheadline.bold().monospacedDigit())
        }
    }

    private var bridgeDiagnostics: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("APP ↔ ESP32 ↔ UNO BRIDGE", systemImage: "cable.connector")
                .font(.caption.bold().monospaced())
                .foregroundStyle(ClinicalTheme.teal)
            if let bridge = robot.bridge {
                diag("Uno telemetry received", "\(bridge.uno_rx_bytes) bytes")
                diag("Commands forwarded", "\(bridge.uno_tx_bytes) bytes")
                diag("App commands received", "\(bridge.ws_commands)")
                Text(bridge.uno_rx_bytes > 0 ? "RX path confirmed. Tap CALL or Drive, then confirm Commands forwarded increases." : "No Uno RX bytes: check S1 is CAM, TX/RX are crossed, and ground is shared.")
                    .font(.caption2)
                    .foregroundStyle(bridge.uno_rx_bytes > 0 ? ClinicalTheme.green : ClinicalTheme.amber)
            } else {
                Text("Waiting for bridge diagnostic payload…")
                    .font(.caption)
                    .foregroundStyle(ClinicalTheme.muted)
            }
        }
        .clinicalCard()
    }

    private var setupDiagnostics: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("ESP32 DIAGNOSTICS", systemImage: "cpu")
                .font(.caption.bold().monospaced())
                .foregroundStyle(ClinicalTheme.teal)
            if let health = robot.health {
                diag("Setup network", health.ap_ssid)
                diag("Robot address", health.ap_ip)
                diag("Camera", health.camera_ok ? "ONLINE" : "UNAVAILABLE")
                diag("PSRAM", health.psram ? "DETECTED" : "NOT DETECTED")
                diag("AP clients", "\(health.ap_clients)")
                diag("Free memory", "\(health.free_heap / 1024) KB")
            } else {
                Text("No /health response yet. Join MedAssist-Robot, then tap Retry.")
                    .font(.caption)
                    .foregroundStyle(ClinicalTheme.muted)
            }
        }
        .clinicalCard()
    }

    private func diag(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(ClinicalTheme.muted)
            Spacer()
            Text(value)
                .font(.caption.bold().monospaced())
        }
    }

    private var incidentHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("INCIDENT HISTORY", systemImage: "clock.arrow.circlepath")
                .font(.caption.bold().monospaced())
                .foregroundStyle(ClinicalTheme.teal)
            if robot.incidents.isEmpty {
                Text("No vision incidents logged.")
                    .font(.caption)
                    .foregroundStyle(ClinicalTheme.muted)
            }
            ForEach(robot.incidents.prefix(12)) { event in
                HStack {
                    Text(event.title.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                    Spacer()
                    Text("\(Int(event.confidence * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(ClinicalTheme.muted)
                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(ClinicalTheme.muted)
                }
            }
        }
        .clinicalCard()
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("NETWORK", systemImage: "wifi")
                .font(.caption.bold().monospaced())
                .foregroundStyle(ClinicalTheme.teal)
            HStack {
                Text(robot.robotHost)
                    .font(.caption.monospaced())
                Spacer()
                Button("EDIT") { editHost = true }
                    .font(.caption.bold())
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("OPEN IPHONE WI-FI SETTINGS", systemImage: "wifi")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(ClinicalTheme.teal)
        }
        .clinicalCard()
        .sheet(isPresented: $editHost) {
            AddressEditor()
        }
    }
}

struct AddressEditor: View {
    @EnvironmentObject var robot: RobotConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Robot Address") {
                    TextField("192.168.4.1", text: $address)
                        .textInputAutocapitalization(.never)
                    Text("Default: join MedAssist-Robot Wi-Fi, use 192.168.4.1.")
                        .font(.caption)
                }
                Section {
                    Button("SAVE AND CONNECT") {
                        robot.robotHost = address
                        robot.disconnect()
                        robot.connect()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Network Link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { address = robot.robotHost }
        }
    }
}
