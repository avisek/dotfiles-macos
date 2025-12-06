#!/usr/bin/env swift

import Foundation

// MARK: - Protocol Message (must match daemon)

struct VolumeMessage: Codable {
    let deviceName: String
    let deviceType: String  // "output" or "input"
    let volume: Float       // 0.0 to 1.0
    let isMuted: Bool
    let supportsVolume: Bool
    let supportsMute: Bool
    let errorMessage: String?  // Optional error message
    
    init(
        deviceName: String,
        deviceType: String,
        volume: Float = 0.0,
        isMuted: Bool = false,
        supportsVolume: Bool = true,
        supportsMute: Bool = true,
        errorMessage: String? = nil
    ) {
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.volume = volume
        self.isMuted = isMuted
        self.supportsVolume = supportsVolume
        self.supportsMute = supportsMute
        self.errorMessage = errorMessage
    }
}

// MARK: - Socket Client

class SocketClient {
    private let socketPath: String
    
    init(socketPath: String) {
        self.socketPath = socketPath
    }
    
    func send(message: VolumeMessage) throws {
        // Create socket
        let clientSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard clientSocket >= 0 else {
            throw NSError(domain: "SocketError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        defer { close(clientSocket) }
        
        // Set socket timeout
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(clientSocket, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(clientSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        // Connect to server
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
        
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(clientSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard connectResult == 0 else {
            throw NSError(domain: "SocketError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to daemon. Is volume-overlay-daemon running?"])
        }
        
        // Encode and send message
        let data = try JSONEncoder().encode(message)
        let bytesWritten = data.withUnsafeBytes { ptr in
            write(clientSocket, ptr.baseAddress!, data.count)
        }
        
        guard bytesWritten == data.count else {
            throw NSError(domain: "SocketError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to send complete message"])
        }
        
        // Read response
        var buffer = [UInt8](repeating: 0, count: 256)
        let bytesRead = read(clientSocket, &buffer, buffer.count - 1)
        
        if bytesRead > 0 {
            let response = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""
            if response.hasPrefix("ERROR") {
                throw NSError(domain: "SocketError", code: 4, userInfo: [NSLocalizedDescriptionKey: response])
            }
        }
    }
}

// MARK: - Argument Parsing

struct Arguments {
    var deviceName: String = ""
    var deviceType: String = "output"
    var volume: Float = 0.0
    var isMuted: Bool = false
    var supportsVolume: Bool = true
    var supportsMute: Bool = true
    var errorMessage: String? = nil
    var showHelp: Bool = false
}

func parseArguments() -> Arguments {
    var args = Arguments()
    let arguments = CommandLine.arguments
    var i = 1
    
    while i < arguments.count {
        let arg = arguments[i]
        
        switch arg {
        case "-n", "--name":
            i += 1
            if i < arguments.count {
                args.deviceName = arguments[i]
            }
        case "-t", "--type":
            i += 1
            if i < arguments.count {
                args.deviceType = arguments[i]
            }
        case "-v", "--volume":
            i += 1
            if i < arguments.count {
                args.volume = Float(arguments[i]) ?? 0.0
            }
        case "-m", "--muted":
            args.isMuted = true
        case "--no-volume-support":
            args.supportsVolume = false
        case "--no-mute-support":
            args.supportsMute = false
        case "-e", "--error":
            i += 1
            if i < arguments.count {
                args.errorMessage = arguments[i]
            }
        case "-h", "--help":
            args.showHelp = true
        default:
            break
        }
        
        i += 1
    }
    
    return args
}

func printHelp() {
    print("""
    Volume Overlay Client
    
    Usage: volume-overlay-client [options]
    
    Options:
      -n, --name <name>       Device name (required)
      -t, --type <type>       Device type: 'output' or 'input' (default: output)
      -v, --volume <value>    Volume level 0.0-1.0 (default: 0.0)
      -m, --muted             Device is muted
      --no-volume-support     Device does not support volume control
      --no-mute-support       Device does not support mute control
      -e, --error <message>   Error message to display
      -h, --help              Show this help
    
    Environment:
      VOLUME_OVERLAY_SOCKET   Path to daemon socket (default: ~/.cache/volume-overlay.sock)
    
    Examples:
      # Show volume at 75% for output device
      volume-overlay-client -n "MacBook Pro Speakers" -t output -v 0.75
      
      # Show muted state for input device
      volume-overlay-client -n "MacBook Pro Microphone" -t input -m
      
      # Show device that doesn't support volume
      volume-overlay-client -n "HDMI Display" -t output --no-volume-support
      
      # Show error message
      volume-overlay-client -n "External Speakers" -t output -e "Device disconnected"
    """)
}

// MARK: - Main

let args = parseArguments()

if args.showHelp {
    printHelp()
    exit(0)
}

guard !args.deviceName.isEmpty else {
    print("Error: Device name is required. Use -n or --name to specify.")
    print("Use -h or --help for usage information.")
    exit(1)
}

// Determine socket path
let socketPath = ProcessInfo.processInfo.environment["VOLUME_OVERLAY_SOCKET"]
    ?? (NSHomeDirectory() + "/.cache/volume-overlay.sock")

// Create message
let message = VolumeMessage(
    deviceName: args.deviceName,
    deviceType: args.deviceType,
    volume: args.volume,
    isMuted: args.isMuted,
    supportsVolume: args.supportsVolume,
    supportsMute: args.supportsMute,
    errorMessage: args.errorMessage
)

// Send message
let client = SocketClient(socketPath: socketPath)

do {
    try client.send(message: message)
} catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
}

