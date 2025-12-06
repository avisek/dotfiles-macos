#!/usr/bin/env swift

import AppKit
import Foundation

// MARK: - Protocol Message

struct VolumeMessage: Codable {
    let deviceName: String
    let deviceType: String  // "output" or "input"
    let volume: Float       // 0.0 to 1.0
    let isMuted: Bool
    let supportsVolume: Bool
    let supportsMute: Bool
    let errorMessage: String?  // Optional error message
}

// MARK: - Volume Overlay Window

class VolumeOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Volume Overlay View

class VolumeOverlayView: NSView {
    private var deviceName: String = ""
    private var deviceType: String = "output"
    private var volume: Float = 0.0
    private var isMuted: Bool = false
    private var supportsVolume: Bool = true
    private var supportsMute: Bool = true
    private var errorMessage: String? = nil
    
    private let backgroundColor = NSColor(white: 0.1, alpha: 0.92)
    private let barBackgroundColor = NSColor(white: 0.3, alpha: 1.0)
    private let barFillColor = NSColor.white
    private let mutedBarFillColor = NSColor(white: 0.5, alpha: 1.0)
    private let textColor = NSColor.white
    private let secondaryTextColor = NSColor(white: 0.7, alpha: 1.0)
    
    private let cornerRadius: CGFloat = 14
    private let padding: CGFloat = 16
    private let barHeight: CGFloat = 6
    private let iconSize: CGFloat = 24
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(message: VolumeMessage) {
        self.deviceName = message.deviceName
        self.deviceType = message.deviceType
        self.volume = message.volume
        self.isMuted = message.isMuted
        self.supportsVolume = message.supportsVolume
        self.supportsMute = message.supportsMute
        self.errorMessage = message.errorMessage
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard NSGraphicsContext.current?.cgContext != nil else { return }
        
        // Draw background
        let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        backgroundColor.setFill()
        backgroundPath.fill()
        
        // Layout calculations
        let contentWidth = bounds.width - (padding * 2)
        let iconX = padding
        let textX = iconX + iconSize + 10
        let percentageWidth: CGFloat = 50
        
        // Draw icon
        let iconY = bounds.height - padding - iconSize
        drawIcon(at: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
        
        // Prepare text attributes
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: textColor
        ]
        let percentageAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: textColor
        ]
        let errorAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: secondaryTextColor
        ]
        
        // Draw device name and status
        let nameY = bounds.height - padding - 18
        
        if let error = errorMessage {
            // Error state - show device name with error
            let displayText = "\(deviceName)"
            let nameString = NSAttributedString(string: displayText, attributes: nameAttributes)
            nameString.draw(at: NSPoint(x: textX, y: nameY))
            
            // Draw error message below
            let errorY = nameY - 18
            let errorString = NSAttributedString(string: error, attributes: errorAttributes)
            errorString.draw(at: NSPoint(x: textX, y: errorY))
        } else if !supportsVolume {
            // Volume not supported
            let displayText = "\(deviceName)"
            let nameString = NSAttributedString(string: displayText, attributes: nameAttributes)
            nameString.draw(at: NSPoint(x: textX, y: nameY))
            
            let errorY = nameY - 18
            let errorString = NSAttributedString(string: "does not support volume", attributes: errorAttributes)
            errorString.draw(at: NSPoint(x: textX, y: errorY))
        } else if isMuted && !supportsMute {
            // Mute not supported (shown when trying to mute)
            let displayText = "\(deviceName)"
            let nameString = NSAttributedString(string: displayText, attributes: nameAttributes)
            nameString.draw(at: NSPoint(x: textX, y: nameY))
            
            let errorY = nameY - 18
            let errorString = NSAttributedString(string: "does not support mute", attributes: errorAttributes)
            errorString.draw(at: NSPoint(x: textX, y: errorY))
        } else {
            // Normal state
            let displayText = deviceName
            let nameString = NSAttributedString(string: displayText, attributes: nameAttributes)
            nameString.draw(at: NSPoint(x: textX, y: nameY))
            
            // Draw percentage
            let percentageText = isMuted ? "Muted" : "\(Int(round(volume * 100)))%"
            let percentageString = NSAttributedString(string: percentageText, attributes: percentageAttributes)
            let percentageX = bounds.width - padding - percentageWidth
            percentageString.draw(at: NSPoint(x: percentageX, y: nameY))
        }
        
        // Draw volume bar
        let barY: CGFloat = padding
        let barWidth = contentWidth
        
        // Bar background
        let barBackgroundRect = NSRect(x: padding, y: barY, width: barWidth, height: barHeight)
        let barBackgroundPath = NSBezierPath(roundedRect: barBackgroundRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
        barBackgroundColor.setFill()
        barBackgroundPath.fill()
        
        // Bar fill
        let fillWidth: CGFloat
        if !supportsVolume || errorMessage != nil {
            fillWidth = barWidth  // Full bar for unsupported
        } else {
            fillWidth = barWidth * CGFloat(volume)
        }
        
        if fillWidth > 0 {
            let barFillRect = NSRect(x: padding, y: barY, width: fillWidth, height: barHeight)
            let barFillPath = NSBezierPath(roundedRect: barFillRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
            
            if isMuted || !supportsVolume || errorMessage != nil {
                mutedBarFillColor.setFill()
            } else {
                barFillColor.setFill()
            }
            barFillPath.fill()
        }
    }
    
    private func drawIcon(at rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        context.saveGState()
        
        let iconColor = isMuted ? secondaryTextColor : textColor
        iconColor.setFill()
        iconColor.setStroke()
        
        if deviceType == "input" {
            drawMicrophoneIcon(in: rect, muted: isMuted)
        } else {
            drawSpeakerIcon(in: rect, muted: isMuted, volume: volume)
        }
        
        context.restoreGState()
    }
    
    private func drawSpeakerIcon(in rect: NSRect, muted: Bool, volume: Float) {
        let centerY = rect.midY
        let scale = rect.width / 24
        
        // Speaker body
        let speakerPath = NSBezierPath()
        let bodyX = rect.minX + 2 * scale
        let bodyWidth = 4 * scale
        let bodyHeight = 8 * scale
        let coneWidth = 6 * scale
        
        // Speaker rectangle
        speakerPath.move(to: NSPoint(x: bodyX, y: centerY - bodyHeight / 2))
        speakerPath.line(to: NSPoint(x: bodyX + bodyWidth, y: centerY - bodyHeight / 2))
        speakerPath.line(to: NSPoint(x: bodyX + bodyWidth + coneWidth, y: centerY - bodyHeight))
        speakerPath.line(to: NSPoint(x: bodyX + bodyWidth + coneWidth, y: centerY + bodyHeight))
        speakerPath.line(to: NSPoint(x: bodyX + bodyWidth, y: centerY + bodyHeight / 2))
        speakerPath.line(to: NSPoint(x: bodyX, y: centerY + bodyHeight / 2))
        speakerPath.close()
        speakerPath.fill()
        
        if muted {
            // Draw X for muted
            let xPath = NSBezierPath()
            xPath.lineWidth = 2 * scale
            xPath.lineCapStyle = .round
            
            let xStart = rect.minX + 16 * scale
            let xSize = 5 * scale
            
            xPath.move(to: NSPoint(x: xStart, y: centerY - xSize))
            xPath.line(to: NSPoint(x: xStart + xSize * 2, y: centerY + xSize))
            xPath.move(to: NSPoint(x: xStart, y: centerY + xSize))
            xPath.line(to: NSPoint(x: xStart + xSize * 2, y: centerY - xSize))
            xPath.stroke()
        } else {
            // Draw sound waves based on volume
            let waveX = rect.minX + 15 * scale
            let wavePath = NSBezierPath()
            wavePath.lineWidth = 1.5 * scale
            wavePath.lineCapStyle = .round
            
            if volume > 0 {
                // First wave (small)
                let wave1Radius = 3 * scale
                wavePath.appendArc(
                    withCenter: NSPoint(x: waveX - 2 * scale, y: centerY),
                    radius: wave1Radius,
                    startAngle: -45,
                    endAngle: 45,
                    clockwise: false
                )
            }
            
            if volume > 0.33 {
                // Second wave (medium)
                wavePath.move(to: NSPoint(x: waveX, y: centerY))
                let wave2Radius = 6 * scale
                wavePath.appendArc(
                    withCenter: NSPoint(x: waveX - 2 * scale, y: centerY),
                    radius: wave2Radius,
                    startAngle: -45,
                    endAngle: 45,
                    clockwise: false
                )
            }
            
            if volume > 0.66 {
                // Third wave (large)
                wavePath.move(to: NSPoint(x: waveX, y: centerY))
                let wave3Radius = 9 * scale
                wavePath.appendArc(
                    withCenter: NSPoint(x: waveX - 2 * scale, y: centerY),
                    radius: wave3Radius,
                    startAngle: -45,
                    endAngle: 45,
                    clockwise: false
                )
            }
            
            wavePath.stroke()
        }
    }
    
    private func drawMicrophoneIcon(in rect: NSRect, muted: Bool) {
        let centerX = rect.midX
        let centerY = rect.midY
        let scale = rect.width / 24
        
        // Microphone body (rounded rectangle)
        let micWidth = 8 * scale
        let micHeight = 12 * scale
        let micRect = NSRect(
            x: centerX - micWidth / 2,
            y: centerY - micHeight / 2 + 2 * scale,
            width: micWidth,
            height: micHeight
        )
        let micPath = NSBezierPath(roundedRect: micRect, xRadius: micWidth / 2, yRadius: micWidth / 2)
        micPath.fill()
        
        // Microphone stand (arc)
        let standPath = NSBezierPath()
        standPath.lineWidth = 1.5 * scale
        standPath.lineCapStyle = .round
        
        let arcRadius = 6 * scale
        standPath.appendArc(
            withCenter: NSPoint(x: centerX, y: centerY + 2 * scale),
            radius: arcRadius,
            startAngle: 180,
            endAngle: 0,
            clockwise: true
        )
        standPath.stroke()
        
        // Stand vertical line
        let linePath = NSBezierPath()
        linePath.lineWidth = 1.5 * scale
        linePath.move(to: NSPoint(x: centerX, y: centerY - 4 * scale))
        linePath.line(to: NSPoint(x: centerX, y: centerY - 8 * scale))
        linePath.stroke()
        
        // Stand base
        let basePath = NSBezierPath()
        basePath.lineWidth = 1.5 * scale
        basePath.lineCapStyle = .round
        basePath.move(to: NSPoint(x: centerX - 4 * scale, y: centerY - 8 * scale))
        basePath.line(to: NSPoint(x: centerX + 4 * scale, y: centerY - 8 * scale))
        basePath.stroke()
        
        if muted {
            // Draw diagonal line for muted
            let mutePath = NSBezierPath()
            mutePath.lineWidth = 2 * scale
            mutePath.lineCapStyle = .round
            
            mutePath.move(to: NSPoint(x: centerX - 8 * scale, y: centerY + 8 * scale))
            mutePath.line(to: NSPoint(x: centerX + 8 * scale, y: centerY - 8 * scale))
            mutePath.stroke()
        }
    }
}

// MARK: - Volume Overlay Controller

class VolumeOverlayController {
    private var window: VolumeOverlayWindow?
    private var overlayView: VolumeOverlayView?
    private var hideTimer: Timer?
    private var fadeOutTimer: Timer?
    
    private let windowWidth: CGFloat = 280
    private let windowHeight: CGFloat = 70
    private let fadeInDuration: TimeInterval = 0.15
    private let fadeOutDuration: TimeInterval = 0.3
    private let hideDelay: TimeInterval = 2.0
    
    init() {
        setupWindow()
    }
    
    private func setupWindow() {
        let window = VolumeOverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.hasShadow = true
        window.isMovable = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        
        let overlayView = VolumeOverlayView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        window.contentView = overlayView
        
        self.window = window
        self.overlayView = overlayView
    }
    
    func showOverlay(with message: VolumeMessage) {
        guard let window = window, let overlayView = overlayView else { return }
        
        // Cancel any pending hide/fade timers
        hideTimer?.invalidate()
        fadeOutTimer?.invalidate()
        
        // Update the view
        overlayView.update(message: message)
        
        // Position window at lower center of screen with mouse
        positionWindow()
        
        // Show window with fade in
        window.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
        
        // Schedule hide
        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { [weak self] _ in
            self?.fadeOutAndHide()
        }
    }
    
    private func positionWindow() {
        guard let window = window else { return }
        
        // Get screen containing mouse
        let mouseLocation = NSEvent.mouseLocation
        var targetScreen = NSScreen.main ?? NSScreen.screens.first!
        
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                targetScreen = screen
                break
            }
        }
        
        // Calculate position (lower center of screen)
        let screenFrame = targetScreen.visibleFrame
        let x = screenFrame.midX - windowWidth / 2
        let y = screenFrame.minY + 80  // 80 points from bottom
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func fadeOutAndHide() {
        guard let window = window else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
        })
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
        
        // Copy socket path to sun_path
        let pathBytes = socketPath.utf8CString
        let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
        pathBytes.withUnsafeBufferPointer { srcBuffer in
            withUnsafeMutableBytes(of: &addr.sun_path) { destBuffer in
                let copyCount = min(srcBuffer.count, sunPathSize)
                for i in 0..<copyCount {
                    destBuffer[i] = UInt8(bitPattern: srcBuffer[i])
                }
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
        
        // Listen
        guard listen(serverSocket, 5) == 0 else {
            close(serverSocket)
            throw NSError(domain: "SocketError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to listen on socket"])
        }
        
        isRunning = true
        
        // Accept connections in background
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptConnections()
        }
        
        print("Volume overlay daemon started on \(socketPath)")
    }
    
    private func acceptConnections() {
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(serverSocket, sockaddrPtr, &clientAddrLen)
                }
            }
            
            if clientSocket >= 0 {
                handleClient(clientSocket)
            }
        }
    }
    
    private func handleClient(_ clientSocket: Int32) {
        defer { close(clientSocket) }
        
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(clientSocket, &buffer, buffer.count - 1)
        
        guard bytesRead > 0 else { return }
        
        let data = Data(bytes: buffer, count: bytesRead)
        
        do {
            let message = try JSONDecoder().decode(VolumeMessage.self, from: data)
            
            // Update UI on main thread
            DispatchQueue.main.async { [weak self] in
                self?.overlayController.showOverlay(with: message)
            }
            
            // Send acknowledgment
            let response = "OK"
            _ = response.withCString { ptr in
                write(clientSocket, ptr, strlen(ptr))
            }
        } catch {
            print("Failed to decode message: \(error)")
            let response = "ERROR: Invalid message format"
            _ = response.withCString { ptr in
                write(clientSocket, ptr, strlen(ptr))
            }
        }
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
    private var overlayController: VolumeOverlayController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Create overlay controller
        overlayController = VolumeOverlayController()
        
        // Determine socket path
        let socketPath = ProcessInfo.processInfo.environment["VOLUME_OVERLAY_SOCKET"]
            ?? (NSHomeDirectory() + "/.cache/volume-overlay.sock")
        
        // Ensure cache directory exists
        let cacheDir = (socketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        
        // Start socket server
        socketServer = SocketServer(socketPath: socketPath, overlayController: overlayController!)
        
        do {
            try socketServer?.start()
        } catch {
            print("Failed to start socket server: \(error)")
            NSApp.terminate(nil)
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

