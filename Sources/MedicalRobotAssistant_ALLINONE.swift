//
//  MedicalRobotAssistant_ALLINONE.swift
//  MedicalRobotAssistant
//
//  Single-file SwiftUI app: models, networking, MJPEG decoding, AI overlay,
//  drive/servo controls, telemetry dashboard, snapshot-to-Photos, detection
//  history log, haptic alerts, and settings — all in one file per request.
//  Split back into separate files later if the project grows; every type
//  below is marked with `// MARK:` so Xcode's jump bar still organizes it.
//
import SwiftUI
import UIKit
import Combine
import Photos

// ============================================================================
// MARK: - App Entry
// ============================================================================

@main
struct MedicalRobotAssistantApp: App {
    @StateObject private var connection = RobotConnectionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connection)
                .preferredColorScheme(.dark)
        }
    }
}

// ============================================================================
// MARK: - Wire Models (mirror the Arduino Uno / ESP32 JSON exactly)
// ============================================================================

struct GyroReading: Codable {
    let ax: Double, ay: Double, az: Double
    let gx: Double, gy: Double, gz: Double
}

struct RobotTelemetry: Codable {
    let T: Int
    let US: Double
    let LT: [Int]
    let GY: GyroReading
    let TIPPED: Int
    let BATT: Double?          // volts — new battery telemetry field
    let MODE: String?          // "manual" | "patrol" — new autonomous mode field

    var isTipped: Bool { TIPPED != 0 }
    var ultrasonicValid: Bool { US > 0 }
    var isPatrolling: Bool { MODE == "patrol" }
}

struct DetectedObject: Codable, Identifiable {
    var id = UUID()
    let label: String
    let conf: Double
    let x: Double, y: Double, w: Double, h: Double
    enum CodingKeys: String, CodingKey { case label, conf, x, y, w, h }
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
}

/// One entry in the on-screen detection history log.
struct DetectionLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let label: String
    let confidence: Double
}

enum InboundMessage {
    case telemetry(RobotTelemetry)
    case detections(DetectionFrame)
    case heartbeat(Heartbeat)
    case unknown(String)

    static func parse(_ text: String) -> InboundMessage {
        guard let data = text.data(using: .utf8) else { return .unknown(text) }
        let decoder = JSONDecoder()
        if text.contains("\"TYPE\":\"detections\"") || text.contains("\"TYPE\": \"detections\"") {
            if let frame = try? decoder.decode(DetectionFrame.self, from: data) { return .detections(frame) }
        } else if text.contains("\"TYPE\":\"heartbeat\"") || text.contains("\"TYPE\": \"heartbeat\"") {
            if let hb = try? decoder.decode(Heartbeat.self, from: data) { return .heartbeat(hb) }
        } else if text.contains("\"US\"") {
            if let telemetry = try? decoder.decode(RobotTelemetry.self, from: data) { return .telemetry(telemetry) }
        }
        return .unknown(text)
    }
}

// MARK: - Outbound commands (matches the Uno's expanded N=101/900/901/902 set)

struct RobotCommand: Codable {
    var H: Int
    var N: Int
    var D1: Int?
    var D2: Int?
    var D3: Int?
}

enum DriveDirection: Int {
    case turnLeft = 1, turnRight = 2, forward = 3, backward = 4
}

enum RobotCommandFactory {
    private static var nextId = 1
    private static func newId() -> Int { nextId += 1; return nextId }

    static func drive(direction: DriveDirection, speed: Int) -> RobotCommand {
        RobotCommand(H: newId(), N: 3, D1: direction.rawValue, D2: speed, D3: nil)
    }
    static func differential(leftSpeed: Int, rightSpeed: Int) -> RobotCommand {
        RobotCommand(H: newId(), N: 4, D1: leftSpeed, D2: rightSpeed, D3: nil)
    }
    static func servo(id: Int, angle: Int) -> RobotCommand {
        RobotCommand(H: newId(), N: 5, D1: id, D2: angle, D3: nil)
    }
    static func stopAll() -> RobotCommand {
        RobotCommand(H: newId(), N: 100, D1: nil, D2: nil, D3: nil)
    }
    static func setPatrolMode(enabled: Bool) -> RobotCommand {
        RobotCommand(H: newId(), N: 101, D1: enabled ? 1 : 0, D2: nil, D3: nil)
    }
    static func setObstacleGuard(enabled: Bool) -> RobotCommand {
        RobotCommand(H: newId(), N: 900, D1: enabled ? 1 : 0, D2: nil, D3: nil)
    }
    static func setReminderMinutes(_ minutes: Int) -> RobotCommand {
        RobotCommand(H: newId(), N: 901, D1: minutes, D2: nil, D3: nil)
    }
    static func buzzerTest(beeps: Int) -> RobotCommand {
        RobotCommand(H: newId(), N: 902, D1: beeps, D2: nil, D3: nil)
    }
}

// ============================================================================
// MARK: - Robot Connection Manager (WebSocket control channel)
// ============================================================================

@MainActor
final class RobotConnectionManager: NSObject, ObservableObject {

    @Published var isConnected = false
    @Published var connectionStatusText = "Disconnected"
    @Published var latestTelemetry: RobotTelemetry?
    @Published var latestDetections: [DetectedObject] = []
    @Published var detectionHistory: [DetectionLogEntry] = []
    @Published var lastHeartbeat: Heartbeat?
    @Published var robotHost: String = "192.168.4.1"

    var streamURL: URL? { URL(string: "http://\(robotHost)/stream") }
    var snapshotURL: URL? { URL(string: "http://\(robotHost)/snapshot") }
    var healthURL: URL? { URL(string: "http://\(robotHost)/health") }

    private var webSocketTask: URLSessionWebSocketTask?
    private var session = URLSession(configuration: .default)
    private var reconnectTimer: Timer?
    private var detectionStaleTimer: Timer?
    private let hapticGenerator = UINotificationFeedbackGenerator()

    func connect() {
        guard let url = URL(string: "ws://\(robotHost)/ws") else { return }
        connectionStatusText = "Connecting…"
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        listen()
        isConnected = true
        connectionStatusText = "Connected"
        scheduleReconnectWatchdog()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        connectionStatusText = "Disconnected"
        reconnectTimer?.invalidate()
    }

    private func scheduleReconnectWatchdog() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.webSocketTask?.state != .running {
                    self.connectionStatusText = "Reconnecting…"
                    self.connect()
                }
            }
        }
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .failure:
                    self.isConnected = false
                    self.connectionStatusText = "Connection lost"
                case .success(let message):
                    switch message {
                    case .string(let text): self.handleInbound(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) { self.handleInbound(text) }
                    @unknown default: break
                    }
                    self.listen()
                }
            }
        }
    }

    private func handleInbound(_ text: String) {
        switch InboundMessage.parse(text) {
        case .telemetry(let telemetry):
            let wasTipped = latestTelemetry?.isTipped ?? false
            latestTelemetry = telemetry
            if telemetry.isTipped && !wasTipped {
                hapticGenerator.notificationOccurred(.error) // new tip event -> haptic alert
            }
        case .detections(let frame):
            latestDetections = frame.objects
            for obj in frame.objects {
                detectionHistory.insert(
                    DetectionLogEntry(timestamp: Date(), label: obj.label, confidence: obj.conf),
                    at: 0)
                if obj.label == "possible_fall" {
                    hapticGenerator.notificationOccurred(.warning)
                }
            }
            if detectionHistory.count > 50 { detectionHistory.removeLast(detectionHistory.count - 50) }
            scheduleDetectionExpiry()
        case .heartbeat(let hb):
            lastHeartbeat = hb
        case .unknown:
            break
        }
    }

    private func scheduleDetectionExpiry() {
        detectionStaleTimer?.invalidate()
        detectionStaleTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.latestDetections = [] }
        }
    }

    // MARK: Sending

    func send(_ command: RobotCommand) {
        guard let data = try? JSONEncoder().encode(command),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { error in
            if let error { print("[WS] send failed: \(error)") }
        }
    }

    func drive(_ direction: DriveDirection, speed: Int = 180) { send(RobotCommandFactory.drive(direction: direction, speed: speed)) }
    func stop() { send(RobotCommandFactory.stopAll()) }
    func setServo(id: Int, angle: Int) { send(RobotCommandFactory.servo(id: id, angle: angle)) }
    func setObstacleGuard(enabled: Bool) { send(RobotCommandFactory.setObstacleGuard(enabled: enabled)) }
    func setPatrolMode(enabled: Bool) { send(RobotCommandFactory.setPatrolMode(enabled: enabled)) }
    func setReminderMinutes(_ minutes: Int) { send(RobotCommandFactory.setReminderMinutes(minutes)) }
    func testBuzzer(beeps: Int = 2) { send(RobotCommandFactory.buzzerTest(beeps: beeps)) }

    /// Local-only command intercepted by the ESP32 (not forwarded to the Uno).
    func requestSnapshotSave() {
        webSocketTask?.send(.string(#"{"LOCAL":"snapshot"}"#)) { _ in }
    }
}

// ============================================================================
// MARK: - MJPEG Stream Loader
// ============================================================================

final class MjpegStreamLoader: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var currentFrame: UIImage?
    @Published var isStreaming = false
    @Published var framesPerSecond: Double = 0

    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private let boundaryMarker = "--123456789000000000000987654321".data(using: .ascii)!
    private var frameCountWindow = 0
    private var fpsWindowStart = Date()

    func start(url: URL) {
        stop()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        task = session.dataTask(with: url)
        task?.resume()
        isStreaming = true
    }

    func stop() {
        task?.cancel()
        task = nil
        buffer.removeAll()
        isStreaming = false
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        extractFrames()
        if buffer.count > 2_000_000 { buffer.removeAll() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { self.isStreaming = false }
    }

    private func extractFrames() {
        while let boundaryRange = buffer.range(of: boundaryMarker) {
            let afterBoundary = buffer[boundaryRange.upperBound...]
            guard let headerEnd = afterBoundary.range(of: "\r\n\r\n".data(using: .ascii)!) else { return }
            let header = afterBoundary[..<headerEnd.lowerBound]
            guard let headerText = String(data: header, encoding: .ascii),
                  let contentLength = parseContentLength(headerText) else {
                buffer.removeSubrange(buffer.startIndex..<boundaryRange.upperBound)
                continue
            }
            let jpegStart = headerEnd.upperBound
            guard buffer.distance(from: jpegStart, to: buffer.endIndex) >= contentLength else { return }
            let jpegEnd = buffer.index(jpegStart, offsetBy: contentLength)
            let jpegData = buffer[jpegStart..<jpegEnd]

            if let image = UIImage(data: Data(jpegData)) {
                DispatchQueue.main.async {
                    self.currentFrame = image
                    self.trackFrameRate()
                }
            }
            buffer.removeSubrange(buffer.startIndex..<jpegEnd)
        }
    }

    private func trackFrameRate() {
        frameCountWindow += 1
        let elapsed = Date().timeIntervalSince(fpsWindowStart)
        if elapsed >= 1.0 {
            framesPerSecond = Double(frameCountWindow) / elapsed
            frameCountWindow = 0
            fpsWindowStart = Date()
        }
    }

    private func parseContentLength(_ header: String) -> Int? {
        for line in header.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                return Int(line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }
}

// ============================================================================
// MARK: - Detection Overlay
// ============================================================================

struct DetectionOverlay: View {
    let detections: [DetectedObject]

    var body: some View {
        GeometryReader { geo in
            ForEach(detections) { detection in
                let rect = CGRect(
                    x: detection.x * geo.size.width, y: detection.y * geo.size.height,
                    width: detection.w * geo.size.width, height: detection.h * geo.size.height)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(color(for: detection.label), lineWidth: 2.5)
                        .frame(width: rect.width, height: rect.height)
                    Text(label(for: detection))
                        .font(.caption2.bold())
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(color(for: detection.label))
                        .foregroundStyle(.white)
                        .offset(y: -18)
                }
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }

    private func label(for detection: DetectedObject) -> String {
        "\(detection.label.replacingOccurrences(of: "_", with: " ")) \(Int(detection.conf * 100))%"
    }
    private func color(for label: String) -> Color {
        switch label {
        case "possible_fall": return .red
        case "red_flag_area": return .orange
        case "person": return .green
        default: return .yellow
        }
    }
}

// ============================================================================
// MARK: - Camera Stream View (video + overlay + snapshot + FPS badge)
// ============================================================================

struct CameraStreamView: View {
    @EnvironmentObject var connection: RobotConnectionManager
    @StateObject private var loader = MjpegStreamLoader()
    @State private var showSnapshotToast = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let frame = loader.currentFrame {
                    Image(uiImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay(DetectionOverlay(detections: connection.latestDetections))
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Connecting to robot camera…").foregroundStyle(.secondary).font(.footnote)
                    }
                }

                VStack {
                    HStack {
                        fpsBadge
                        Spacer()
                        snapshotButton
                    }
                    .padding(8)
                    Spacer()
                    if showSnapshotToast {
                        Text("Saved to Photos")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.green, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(.bottom, 8)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { if let url = connection.streamURL { loader.start(url: url) } }
        .onDisappear { loader.stop() }
        .onChange(of: connection.robotHost) { _ in
            if let url = connection.streamURL { loader.start(url: url) }
        }
    }

    private var fpsBadge: some View {
        Text(loader.isStreaming ? String(format: "%.0f fps", loader.framesPerSecond) : "offline")
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
    }

    private var snapshotButton: some View {
        Button {
            saveCurrentFrame()
        } label: {
            Image(systemName: "camera.fill")
                .padding(8)
                .background(.black.opacity(0.55), in: Circle())
                .foregroundStyle(.white)
        }
    }

    /// Saves the currently displayed frame to the Photos library — useful
    /// for a caregiver to keep a timestamped record of what the robot saw.
    private func saveCurrentFrame() {
        guard let image = loader.currentFrame else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { success, _ in
                if success {
                    DispatchQueue.main.async {
                        showSnapshotToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showSnapshotToast = false }
                    }
                }
            })
        }
    }
}

// ============================================================================
// MARK: - Control Pad (drive, servo, patrol mode, buzzer, reminder)
// ============================================================================

struct ControlPadView: View {
    @EnvironmentObject var connection: RobotConnectionManager
    @State private var driveSpeed: Double = 180
    @State private var panAngle: Double = 90
    @State private var tiltAngle: Double = 90
    @State private var obstacleGuardOn = true
    @State private var patrolModeOn = false
    @State private var reminderMinutes: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            speedSlider
            dPad

            Button(role: .destructive) { connection.stop() } label: {
                Label("Emergency Stop", systemImage: "octagon.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Toggle("Obstacle Auto-Stop", isOn: $obstacleGuardOn)
                .onChange(of: obstacleGuardOn) { connection.setObstacleGuard(enabled: $0) }

            Toggle("Autonomous Line Patrol", isOn: $patrolModeOn)
                .onChange(of: patrolModeOn) { connection.setPatrolMode(enabled: $0) }

            servoControls
            medicineReminderControl
            buzzerTestButton
        }
        .padding()
    }

    private var speedSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Drive Speed: \(Int(driveSpeed))").font(.caption).foregroundStyle(.secondary)
            Slider(value: $driveSpeed, in: 60...255, step: 5)
        }
    }

    private var dPad: some View {
        VStack(spacing: 10) {
            directionButton(.forward, systemImage: "chevron.up")
            HStack(spacing: 40) {
                directionButton(.turnLeft, systemImage: "chevron.left")
                directionButton(.turnRight, systemImage: "chevron.right")
            }
            directionButton(.backward, systemImage: "chevron.down")
        }
    }

    private func directionButton(_ direction: DriveDirection, systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title)
            .frame(width: 64, height: 64)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in connection.drive(direction, speed: Int(driveSpeed)) }
                    .onEnded { _ in connection.stop() }
            )
    }

    private var servoControls: some View {
        VStack(spacing: 12) {
            Text("Camera Arm").font(.subheadline.bold())
            VStack(alignment: .leading, spacing: 4) {
                Text("Pan: \(Int(panAngle))°").font(.caption).foregroundStyle(.secondary)
                Slider(value: $panAngle, in: 0...180, step: 1) { editing in
                    if !editing { connection.setServo(id: 1, angle: Int(panAngle)) }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Tilt: \(Int(tiltAngle))°").font(.caption).foregroundStyle(.secondary)
                Slider(value: $tiltAngle, in: 0...180, step: 1) { editing in
                    if !editing { connection.setServo(id: 2, angle: Int(tiltAngle)) }
                }
            }
        }
    }

    private var medicineReminderControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reminderMinutes == 0 ? "Medicine Reminder: Off"
                                       : "Medicine Reminder: every \(Int(reminderMinutes)) min")
                .font(.caption).foregroundStyle(.secondary)
            Slider(value: $reminderMinutes, in: 0...180, step: 5) { editing in
                if !editing { connection.setReminderMinutes(Int(reminderMinutes)) }
            }
        }
    }

    private var buzzerTestButton: some View {
        Button {
            connection.testBuzzer(beeps: 2)
        } label: {
            Label("Test Buzzer", systemImage: "speaker.wave.2.fill")
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }
}

// ============================================================================
// MARK: - Telemetry Panel (sensors, battery, mode, link health)
// ============================================================================

struct TelemetryPanelView: View {
    @EnvironmentObject var connection: RobotConnectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusRow

            if let telemetry = connection.latestTelemetry {
                if telemetry.isTipped { tippedWarning }

                metricRow(icon: "ruler", title: "Obstacle Distance",
                          value: telemetry.ultrasonicValid ? String(format: "%.1f cm", telemetry.US) : "No echo")

                if let batt = telemetry.BATT {
                    batteryRow(batt)
                }

                metricRow(icon: telemetry.isPatrolling ? "figure.walk.motion" : "hand.point.up.left.fill",
                          title: "Drive Mode", value: telemetry.isPatrolling ? "Autonomous Patrol" : "Manual")

                lineTrackingRow(telemetry.LT)
                gyroRow(telemetry.GY)
            } else {
                Text("Waiting for sensor telemetry…").font(.footnote).foregroundStyle(.secondary)
            }

            if let hb = connection.lastHeartbeat {
                Divider()
                metricRow(icon: "wifi", title: "Wi-Fi RSSI", value: "\(hb.rssi) dBm")
                metricRow(icon: "person.2.fill", title: "Clients", value: "\(hb.clients)")
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusRow: some View {
        HStack {
            Circle().fill(connection.isConnected ? Color.green : Color.red).frame(width: 10, height: 10)
            Text(connection.connectionStatusText).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var tippedWarning: some View {
        Label("Chassis tip / fall detected!", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(8).frame(maxWidth: .infinity)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
    }

    private func metricRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 20)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospacedDigit().bold())
        }
    }

    private func batteryRow(_ volts: Double) -> some View {
        let isLow = volts < 6.6
        return HStack {
            Image(systemName: isLow ? "battery.25" : "battery.75").frame(width: 20)
                .foregroundStyle(isLow ? .red : .primary)
            Text("Battery").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.2f V", volts))
                .font(.callout.monospacedDigit().bold())
                .foregroundStyle(isLow ? .red : .primary)
        }
    }

    private func lineTrackingRow(_ values: [Int]) -> some View {
        HStack {
            Image(systemName: "road.lanes").frame(width: 20)
            Text("Line Sensors (L/M/R)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                Text("\(v)").font(.caption.monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func gyroRow(_ gyro: GyroReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Gyro / Accel", systemImage: "gyroscope").font(.caption).foregroundStyle(.secondary)
            Text(String(format: "accel  x:%.2f  y:%.2f  z:%.2f g", gyro.ax, gyro.ay, gyro.az)).font(.caption2.monospacedDigit())
            Text(String(format: "gyro   x:%.1f  y:%.1f  z:%.1f °/s", gyro.gx, gyro.gy, gyro.gz)).font(.caption2.monospacedDigit())
        }
    }
}

// ============================================================================
// MARK: - Detection History Log
// ============================================================================

struct DetectionHistoryView: View {
    @EnvironmentObject var connection: RobotConnectionManager

    var body: some View {
        List(connection.detectionHistory) { entry in
            HStack {
                Image(systemName: icon(for: entry.label)).foregroundStyle(color(for: entry.label))
                VStack(alignment: .leading) {
                    Text(entry.label.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline.bold())
                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(entry.confidence * 100))%").font(.caption.monospacedDigit())
            }
        }
        .navigationTitle("Detection History")
         .overlay {
            if connection.detectionHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No detections yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }

    private func icon(for label: String) -> String {
        switch label {
        case "possible_fall": return "exclamationmark.triangle.fill"
        case "red_flag_area": return "bandage.fill"
        case "person": return "figure.stand"
        default: return "questionmark.circle"
        }
    }
    private func color(for label: String) -> Color {
        switch label {
        case "possible_fall": return .red
        case "red_flag_area": return .orange
        case "person": return .green
        default: return .yellow
        }
    }
}

// ============================================================================
// MARK: - Root Content View
// ============================================================================

struct ContentView: View {
    @EnvironmentObject var connection: RobotConnectionManager
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    CameraStreamView()
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)

                    TelemetryPanelView().padding(.horizontal)
                    ControlPadView()

                    NavigationLink {
                        DetectionHistoryView()
                    } label: {
                        Label("View Detection History", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }
            .navigationTitle("Medical Robot Assistant")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onAppear { if !connection.isConnected { connection.connect() } }
        }
    }
}

// ============================================================================
// MARK: - Settings Sheet
// ============================================================================

struct SettingsView: View {
    @EnvironmentObject var connection: RobotConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var hostText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Robot Address") {
                    TextField("IP address or hostname", text: $hostText)
                        .keyboardType(.default)
                        .textInputAutocapitalization(.never)
                    Text("Default SoftAP: 192.168.4.1  •  mDNS: medassist.local")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section {
                    Button("Reconnect") {
                        connection.robotHost = hostText
                        connection.disconnect()
                        connection.connect()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear { hostText = connection.robotHost }
        }
    }
}

#Preview {
    ContentView().environmentObject(RobotConnectionManager())
}
