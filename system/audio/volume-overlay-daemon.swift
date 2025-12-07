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

// MARK: - Volume Overlay View

class VolumeOverlayView: NSView {
    private var data: OverlayData?
    
    private let padding: CGFloat = 16
    private let iconSize: CGFloat = 24
    private let barHeight: CGFloat = 4
    private let cornerRadius: CGFloat = 12
    private let spacing: CGFloat = 10
    
    func update(with data: OverlayData) {
        self.data = data
        needsDisplay = true
        
        // Calculate required width based on content
        let requiredWidth = calculateRequiredWidth(for: data)
        let newFrame = NSRect(x: 0, y: 0, width: requiredWidth, height: 60)
        
        if frame.size != newFrame.size {
            setFrameSize(newFrame.size)
            window?.setContentSize(newFrame.size)
        }
    }
    
    private func calculateRequiredWidth(for data: OverlayData) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        
        let text: String
        switch (data.volume, data.muted) {
        case (.unsupported, _):
            text = "\(data.name) does not support volume"
        case (_, .unsupported):
            text = "\(data.name) does not support muting"
        default:
            // Name + percentage
            let percentage = volumePercentage(data.volume)
            text = "\(data.name)\(percentage)"
        }
        
        let textWidth = (text as NSString).size(withAttributes: attrs).width
        let minWidth: CGFloat = 320
        let contentWidth = padding + iconSize + spacing + textWidth + spacing + padding
        
        return max(minWidth, contentWidth)
    }
    
    private func volumePercentage(_ volume: VolumeState) -> String {
        switch volume {
        case .level(let value):
            return "\(Int(round(value * 100)))%"
        case .unsupported:
            return ""
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let data = data else { return }
        
        // Draw background
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(white: 0.1, alpha: 0.92).setFill()
        bgPath.fill()
        
        // Draw border
        NSColor(white: 0.3, alpha: 0.5).setStroke()
        bgPath.lineWidth = 0.5
        bgPath.stroke()
        
        // Calculate layout
        let iconRect = NSRect(
            x: padding,
            y: bounds.height - padding - iconSize + 4,
            width: iconSize,
            height: iconSize
        )
        
        // Draw icon
        drawIcon(in: iconRect, data: data)
        
        // Draw text
        let textX = iconRect.maxX + spacing
        let textY = bounds.height - padding
        
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let smallFont = NSFont.systemFont(ofSize: 13, weight: .regular)
        
        switch (data.volume, data.muted) {
        case (.unsupported, _):
            // Volume unsupported message
            let text = "\(data.name) does not support volume"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.7)
            ]
            (text as NSString).draw(at: NSPoint(x: textX, y: textY - 16), withAttributes: attrs)
            
            // Draw full orange bar
            drawVolumeBar(progress: 1.0, color: NSColor.orange.withAlphaComponent(0.6))
            
        case (_, .unsupported):
            // Mute unsupported message
            let text = "\(data.name) does not support muting"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.7)
            ]
            (text as NSString).draw(at: NSPoint(x: textX, y: textY - 16), withAttributes: attrs)
            
            // Draw full orange bar
            drawVolumeBar(progress: 1.0, color: NSColor.orange.withAlphaComponent(0.6))
            
        case (.level(let value), let muteState):
            // Device name
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]
            (data.name as NSString).draw(at: NSPoint(x: textX, y: textY - 16), withAttributes: nameAttrs)
            
            // Percentage or "Muted"
            let rightText: String
            let rightColor: NSColor
            
            if case .muted = muteState {
                rightText = "Muted"
                rightColor = NSColor.white.withAlphaComponent(0.6)
            } else {
                rightText = "\(Int(round(value * 100)))%"
                rightColor = NSColor.white.withAlphaComponent(0.8)
            }
            
            let rightAttrs: [NSAttributedString.Key: Any] = [
                .font: smallFont,
                .foregroundColor: rightColor
            ]
            let rightSize = (rightText as NSString).size(withAttributes: rightAttrs)
            let rightX = bounds.width - padding - rightSize.width
            (rightText as NSString).draw(at: NSPoint(x: rightX, y: textY - 16), withAttributes: rightAttrs)
            
            // Draw volume bar
            let barColor: NSColor
            if case .muted = muteState {
                barColor = NSColor.white.withAlphaComponent(0.3)
            } else {
                barColor = NSColor.white
            }
            drawVolumeBar(progress: value, color: barColor)
        }
    }
    
    private func drawIcon(in rect: NSRect, data: OverlayData) {
        let isMuted = data.muted == .muted
        let isInput = data.type == .input
        
        NSGraphicsContext.saveGraphicsState()
        
        let iconColor: NSColor
        if isMuted {
            iconColor = NSColor.white.withAlphaComponent(0.5)
        } else {
            iconColor = NSColor.white
        }
        iconColor.setFill()
        iconColor.setStroke()
        
        if isInput {
            // Draw microphone icon
            drawMicrophoneIcon(in: rect, muted: isMuted)
        } else {
            // Draw speaker icon
            drawSpeakerIcon(in: rect, data: data, muted: isMuted)
        }
        
        NSGraphicsContext.restoreGraphicsState()
    }
    
    private func drawSpeakerIcon(in rect: NSRect, data: OverlayData, muted: Bool) {
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
            let volume: Float
            if case .level(let v) = data.volume {
                volume = v
            } else {
                volume = 1.0
            }
            
            if volume > 0 {
                // First wave (small)
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
            
            if volume > 0.33 {
                // Second wave (medium)
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
            
            if volume > 0.66 {
                // Third wave (large)
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
    
    private func drawMicrophoneIcon(in rect: NSRect, muted: Bool) {
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
            // Draw diagonal line through microphone
            let muteLine = NSBezierPath()
            muteLine.lineWidth = 2 * scale
            muteLine.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.5).setStroke()
            muteLine.move(to: NSPoint(x: rect.minX + 4 * scale, y: rect.maxY - 4 * scale))
            muteLine.line(to: NSPoint(x: rect.maxX - 4 * scale, y: rect.minY + 4 * scale))
            muteLine.stroke()
        }
    }
    
    private func drawVolumeBar(progress: Float, color: NSColor) {
        let barY: CGFloat = padding - 2
        let barX: CGFloat = padding
        let barWidth = bounds.width - (padding * 2)
        
        // Background bar
        let bgRect = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
        NSColor.white.withAlphaComponent(0.2).setFill()
        bgPath.fill()
        
        // Progress bar
        if progress > 0 {
            let progressWidth = barWidth * CGFloat(min(max(progress, 0), 1))
            let progressRect = NSRect(x: barX, y: barY, width: progressWidth, height: barHeight)
            let progressPath = NSBezierPath(roundedRect: progressRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
            color.setFill()
            progressPath.fill()
        }
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
            overlayView = VolumeOverlayView(frame: window!.contentView!.bounds)
            overlayView!.autoresizingMask = [.width, .height]
            window!.contentView = overlayView
        }
        
        guard let window = window, let overlayView = overlayView else { return }
        
        // Update content
        overlayView.update(with: data)
        
        // Position window at lower-center of screen with mouse
        positionWindow(window)
        
        // Show and fade in
        if !window.isVisible || isFadingOut {
            isFadingOut = false
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

