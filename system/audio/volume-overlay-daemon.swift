import AppKit
import Foundation

// MARK: - Data Types

enum DeviceType: String {
    case output
    case input
}

enum VolumeState {
    case level(Float)
    case unsupported
}

enum MuteState {
    case muted
    case unmuted
    case unsupported
}

struct OverlayData {
    let name: String
    let type: DeviceType
    let volume: VolumeState
    let muted: MuteState
}

// MARK: - Icon View (Custom Drawing)

class IconView: NSView {
    var deviceType: DeviceType = .output
    var volume: VolumeState = .level(1.0)
    var muted: MuteState = .unmuted
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: 24, height: 24)
    }
    
    func update(type: DeviceType, volume: VolumeState, muted: MuteState) {
        self.deviceType = type
        self.volume = volume
        self.muted = muted
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let isMuted = muted == .muted
        
        let iconColor: NSColor
        if isMuted {
            iconColor = NSColor.labelColor.withAlphaComponent(0.5)
        } else {
            iconColor = NSColor.labelColor
        }
        iconColor.setFill()
        iconColor.setStroke()
        
        if deviceType == .input {
            drawMicrophoneIcon(muted: isMuted)
        } else {
            drawSpeakerIcon(muted: isMuted)
        }
    }
    
    private func drawSpeakerIcon(muted: Bool) {
        let rect = bounds
        let centerY = rect.midY
        let scale = rect.width / 24
        
        // Speaker body
        let bodyPath = NSBezierPath()
        bodyPath.move(to: NSPoint(x: rect.minX + 3 * scale, y: centerY + 3 * scale))
        bodyPath.line(to: NSPoint(x: rect.minX + 7 * scale, y: centerY + 3 * scale))
        bodyPath.line(to: NSPoint(x: rect.minX + 12 * scale, y: centerY + 7 * scale))
        bodyPath.line(to: NSPoint(x: rect.minX + 12 * scale, y: centerY - 7 * scale))
        bodyPath.line(to: NSPoint(x: rect.minX + 7 * scale, y: centerY - 3 * scale))
        bodyPath.line(to: NSPoint(x: rect.minX + 3 * scale, y: centerY - 3 * scale))
        bodyPath.close()
        bodyPath.fill()
        
        if muted {
            // Draw X for mute
            let xPath = NSBezierPath()
            xPath.lineWidth = 1.5 * scale
            xPath.lineCapStyle = .round
            
            xPath.move(to: NSPoint(x: rect.minX + 15 * scale, y: centerY + 3 * scale))
            xPath.line(to: NSPoint(x: rect.minX + 21 * scale, y: centerY - 3 * scale))
            xPath.move(to: NSPoint(x: rect.minX + 21 * scale, y: centerY + 3 * scale))
            xPath.line(to: NSPoint(x: rect.minX + 15 * scale, y: centerY - 3 * scale))
            xPath.stroke()
        } else {
            // Draw sound waves based on volume
            let vol: Float
            if case .level(let v) = volume {
                vol = v
            } else {
                vol = 1.0
            }
            
            if vol > 0 {
                let wave1 = NSBezierPath()
                wave1.lineWidth = 1.5 * scale
                wave1.lineCapStyle = .round
                wave1.appendArc(
                    withCenter: NSPoint(x: rect.minX + 12 * scale, y: centerY),
                    radius: 3 * scale,
                    startAngle: -40,
                    endAngle: 40,
                    clockwise: false
                )
                wave1.stroke()
            }
            
            if vol > 0.33 {
                let wave2 = NSBezierPath()
                wave2.lineWidth = 1.5 * scale
                wave2.lineCapStyle = .round
                wave2.appendArc(
                    withCenter: NSPoint(x: rect.minX + 12 * scale, y: centerY),
                    radius: 6.5 * scale,
                    startAngle: -40,
                    endAngle: 40,
                    clockwise: false
                )
                wave2.stroke()
            }
            
            if vol > 0.66 {
                let wave3 = NSBezierPath()
                wave3.lineWidth = 1.5 * scale
                wave3.lineCapStyle = .round
                wave3.appendArc(
                    withCenter: NSPoint(x: rect.minX + 12 * scale, y: centerY),
                    radius: 10 * scale,
                    startAngle: -40,
                    endAngle: 40,
                    clockwise: false
                )
                wave3.stroke()
            }
        }
    }
    
    private func drawMicrophoneIcon(muted: Bool) {
        let rect = bounds
        let centerX = rect.midX
        let centerY = rect.midY
        let scale = rect.width / 24
        
        // Microphone body (capsule)
        let micBody = NSBezierPath(
            roundedRect: NSRect(
                x: centerX - 3 * scale,
                y: centerY - 2 * scale,
                width: 6 * scale,
                height: 11 * scale
            ),
            xRadius: 3 * scale,
            yRadius: 3 * scale
        )
        micBody.fill()
        
        // Microphone stand (arc)
        let standArc = NSBezierPath()
        standArc.lineWidth = 1.5 * scale
        standArc.lineCapStyle = .round
        standArc.appendArc(
            withCenter: NSPoint(x: centerX, y: centerY + 1 * scale),
            radius: 6 * scale,
            startAngle: 0,
            endAngle: 180,
            clockwise: true
        )
        standArc.stroke()
        
        // Stand base
        let standLine = NSBezierPath()
        standLine.lineWidth = 1.5 * scale
        standLine.lineCapStyle = .round
        standLine.move(to: NSPoint(x: centerX, y: centerY - 5 * scale))
        standLine.line(to: NSPoint(x: centerX, y: centerY - 8 * scale))
        standLine.stroke()
        
        if muted {
            let muteLine = NSBezierPath()
            muteLine.lineWidth = 2 * scale
            muteLine.lineCapStyle = .round
            NSColor.labelColor.withAlphaComponent(0.5).setStroke()
            muteLine.move(to: NSPoint(x: rect.minX + 4 * scale, y: rect.maxY - 4 * scale))
            muteLine.line(to: NSPoint(x: rect.maxX - 4 * scale, y: rect.minY + 4 * scale))
            muteLine.stroke()
        }
    }
}

// MARK: - Volume Bar View

class VolumeBarView: NSView {
    var progress: Float = 1.0
    var barColor: NSColor = .labelColor
    var isWarning: Bool = false
    
    private let barHeight: CGFloat = 4
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: barHeight)
    }
    
    func update(progress: Float, muted: Bool, isWarning: Bool) {
        self.progress = progress
        self.isWarning = isWarning
        
        if isWarning {
            self.barColor = NSColor.systemOrange.withAlphaComponent(0.6)
        } else if muted {
            self.barColor = NSColor.labelColor.withAlphaComponent(0.3)
        } else {
            self.barColor = NSColor.labelColor
        }
        
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let barRect = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        
        // Background bar
        let bgPath = NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        bgPath.fill()
        
        // Progress bar
        if progress > 0 {
            let progressWidth = bounds.width * CGFloat(min(max(progress, 0), 1))
            let progressRect = NSRect(x: 0, y: 0, width: progressWidth, height: barHeight)
            let progressPath = NSBezierPath(roundedRect: progressRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
            barColor.setFill()
            progressPath.fill()
        }
    }
}

// MARK: - Volume Overlay Content View

class VolumeOverlayContentView: NSView {
    private let iconView = IconView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let volumeBar = VolumeBarView()
    
    private var statusLabelTrailingToSuperview: NSLayoutConstraint!
    private var statusLabelTrailingToStatusLabel: NSLayoutConstraint!
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        // Configure icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        // Configure name label
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        nameLabel.textColor = NSColor.labelColor
        nameLabel.backgroundColor = .clear
        nameLabel.isBezeled = false
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        // Configure status label (percentage/muted/unsupported suffix)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.backgroundColor = .clear
        statusLabel.isBezeled = false
        statusLabel.isEditable = false
        statusLabel.isSelectable = false
        statusLabel.alignment = .right
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        // Configure volume bar
        volumeBar.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(statusLabel)
        addSubview(volumeBar)
        
        // Create constraints
        statusLabelTrailingToSuperview = statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        statusLabelTrailingToStatusLabel = statusLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 0)
        
        NSLayoutConstraint.activate([
            // Icon constraints
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -2),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            // Name label constraints
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            nameLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            
            // Status label constraints
            statusLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            statusLabelTrailingToSuperview,
            
            // Volume bar constraints
            volumeBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            volumeBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            volumeBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            volumeBar.heightAnchor.constraint(equalToConstant: 4),
        ])
    }
    
    func update(with data: OverlayData) {
        iconView.update(type: data.type, volume: data.volume, muted: data.muted)
        
        let isMuted = data.muted == .muted
        
        switch (data.volume, data.muted) {
        case (.unsupported, _):
            nameLabel.stringValue = data.name
            nameLabel.textColor = NSColor.labelColor
            statusLabel.stringValue = " does not support volume"
            statusLabel.textColor = NSColor.secondaryLabelColor
            volumeBar.update(progress: 1.0, muted: false, isWarning: true)
            
            // Status follows name directly
            statusLabelTrailingToSuperview.isActive = false
            statusLabelTrailingToStatusLabel.isActive = true
            nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            
        case (_, .unsupported):
            nameLabel.stringValue = data.name
            nameLabel.textColor = NSColor.labelColor
            statusLabel.stringValue = " does not support muting"
            statusLabel.textColor = NSColor.secondaryLabelColor
            volumeBar.update(progress: 1.0, muted: false, isWarning: true)
            
            // Status follows name directly
            statusLabelTrailingToSuperview.isActive = false
            statusLabelTrailingToStatusLabel.isActive = true
            nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            
        case (.level(let value), let muteState):
            nameLabel.stringValue = data.name
            nameLabel.textColor = NSColor.labelColor
            
            if case .muted = muteState {
                statusLabel.stringValue = "Muted"
                statusLabel.textColor = NSColor.secondaryLabelColor
            } else {
                statusLabel.stringValue = "\(Int(round(value * 100)))%"
                statusLabel.textColor = NSColor.labelColor.withAlphaComponent(0.8)
            }
            
            volumeBar.update(progress: value, muted: isMuted, isWarning: false)
            
            // Status aligned to trailing edge
            statusLabelTrailingToStatusLabel.isActive = false
            statusLabelTrailingToSuperview.isActive = true
            nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }
        
        needsLayout = true
    }
    
    override var intrinsicContentSize: NSSize {
        let nameSize = nameLabel.intrinsicContentSize
        let statusSize = statusLabel.intrinsicContentSize
        
        let textWidth = nameSize.width + statusSize.width
        let minWidth: CGFloat = 320
        let contentWidth = 16 + 24 + 10 + textWidth + 16
        
        return NSSize(width: max(minWidth, contentWidth), height: 60)
    }
}

// MARK: - Volume Overlay Window

class VolumeOverlayWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }
}

// MARK: - Volume Overlay View (Container with Blur)

class VolumeOverlayView: NSView {
    private let visualEffectView: NSVisualEffectView
    private let contentView: VolumeOverlayContentView
    private let cornerRadius: CGFloat = 14
    
    override init(frame frameRect: NSRect) {
        visualEffectView = NSVisualEffectView()
        contentView = VolumeOverlayContentView()
        
        super.init(frame: frameRect)
        
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        visualEffectView = NSVisualEffectView()
        contentView = VolumeOverlayContentView()
        
        super.init(coder: coder)
        
        setupViews()
    }
    
    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        
        // Configure visual effect view (blur background)
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.masksToBounds = true
        
        // Configure content view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(visualEffectView)
        addSubview(contentView)
        
        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    func update(with data: OverlayData) {
        contentView.update(with: data)
        
        // Update window size based on content
        let newSize = contentView.intrinsicContentSize
        if let window = window {
            let currentFrame = window.frame
            let newFrame = NSRect(
                x: currentFrame.origin.x - (newSize.width - currentFrame.width) / 2,
                y: currentFrame.origin.y,
                width: newSize.width,
                height: newSize.height
            )
            window.setFrame(newFrame, display: true)
        }
        
        invalidateIntrinsicContentSize()
    }
    
    override var intrinsicContentSize: NSSize {
        return contentView.intrinsicContentSize
    }
}

// MARK: - Volume Overlay Controller

class VolumeOverlayController {
    private var window: VolumeOverlayWindow?
    private var overlayView: VolumeOverlayView?
    private var hideTimer: Timer?
    private var isFadingOut = false
    
    private let fadeInDuration: TimeInterval = 0.15
    private let fadeOutDuration: TimeInterval = 0.3
    private let hideDelay: TimeInterval = 2.0
    
    func show(data: OverlayData) {
        DispatchQueue.main.async { [weak self] in
            self?.showOverlay(data: data)
        }
    }
    
    private func showOverlay(data: OverlayData) {
        // Cancel any pending hide
        hideTimer?.invalidate()
        hideTimer = nil
        
        // Create window if needed
        if window == nil {
            window = VolumeOverlayWindow()
            overlayView = VolumeOverlayView(frame: NSRect(x: 0, y: 0, width: 320, height: 60))
            window!.contentView = overlayView
        }
        
        guard let window = window, let overlayView = overlayView else { return }
        
        // Update content
        overlayView.update(with: data)
        
        // Position window at lower-center of screen with mouse
        positionWindow(window)
        
        // Show and fade in
        if isFadingOut {
            // Interrupt fade out - animate from current alpha to 1.0
            isFadingOut = false
            let currentAlpha = window.alphaValue
            let remainingFade = 1.0 - currentAlpha
            let duration = fadeInDuration * remainingFade
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
            }
        } else if !window.isVisible {
            // Fresh show - start from alpha 0
            window.alphaValue = 0
            window.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeInDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
            }
        }
        
        // Schedule hide
        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { [weak self] _ in
            self?.hideOverlay()
        }
    }
    
    private func hideOverlay() {
        guard let window = window, window.isVisible else { return }
        
        isFadingOut = true
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            if self?.isFadingOut == true {
                window.orderOut(nil)
                self?.isFadingOut = false
            }
        })
    }
    
    private func positionWindow(_ window: NSWindow) {
        // Find screen containing mouse
        let mouseLocation = NSEvent.mouseLocation
        var targetScreen = NSScreen.main ?? NSScreen.screens.first!
        
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                targetScreen = screen
                break
            }
        }
        
        let screenFrame = targetScreen.visibleFrame
        let windowSize = window.frame.size
        
        // Position at lower-center
        let x = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
        let y = screenFrame.origin.y + 80
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Socket Server

class SocketServer {
    private let socketPath: String
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private let overlayController: VolumeOverlayController
    
    init(socketPath: String, overlayController: VolumeOverlayController) {
        self.socketPath = socketPath
        self.overlayController = overlayController
    }
    
    func start() throws {
        // Remove existing socket file
        unlink(socketPath)
        
        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw NSError(domain: "SocketError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        
        // Bind socket
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            socketPath.withCString { cstr in
                strcpy(ptr, cstr)
            }
        }
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard bindResult == 0 else {
            close(serverSocket)
            throw NSError(domain: "SocketError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind socket"])
        }
        
        // Set socket permissions (world-writable)
        chmod(socketPath, 0o777)
        
        // Listen
        guard listen(serverSocket, 5) == 0 else {
            close(serverSocket)
            throw NSError(domain: "SocketError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to listen on socket"])
        }
        
        isRunning = true
        
        // Accept connections in background
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.acceptLoop()
        }
        
        print("Volume overlay daemon started, listening on \(socketPath)")
    }
    
    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(serverSocket, sockaddrPtr, &clientAddrLen)
                }
            }
            
            guard clientSocket >= 0 else { continue }
            
            // Read data
            var buffer = [CChar](repeating: 0, count: 4096)
            let bytesRead = read(clientSocket, &buffer, buffer.count - 1)
            close(clientSocket)
            
            guard bytesRead > 0 else { continue }
            
            let message = String(cString: buffer)
            
            if let data = parseMessage(message) {
                overlayController.show(data: data)
            }
        }
    }
    
    private func parseMessage(_ message: String) -> OverlayData? {
        var name: String?
        var type: DeviceType = .output
        var volume: VolumeState = .level(1.0)
        var muted: MuteState = .unmuted
        
        let components = message.components(separatedBy: "\n")
        
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            if trimmed.hasPrefix("name:") {
                name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("type:") {
                let typeStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                type = typeStr == "input" ? .input : .output
            } else if trimmed.hasPrefix("volume:") {
                let volumeStr = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                if volumeStr == "unsupported" {
                    volume = .unsupported
                } else if let value = Float(volumeStr) {
                    volume = .level(min(max(value, 0), 1))
                }
            } else if trimmed.hasPrefix("muted:") {
                let mutedStr = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                switch mutedStr {
                case "true":
                    muted = .muted
                case "unsupported":
                    muted = .unsupported
                default:
                    muted = .unmuted
                }
            }
        }
        
        guard let deviceName = name, !deviceName.isEmpty else {
            return nil
        }
        
        return OverlayData(name: deviceName, type: type, volume: volume, muted: muted)
    }
    
    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(socketPath)
    }
}

// MARK: - Application Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var socketServer: SocketServer?
    private let overlayController = VolumeOverlayController()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Start socket server
        let socketPath = "/tmp/volume-overlay.sock"
        socketServer = SocketServer(socketPath: socketPath, overlayController: overlayController)
        
        do {
            try socketServer?.start()
        } catch {
            print("Failed to start socket server: \(error)")
            NSApp.terminate(nil)
        }
        
        // Handle termination signals
        signal(SIGINT) { _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
        signal(SIGTERM) { _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
