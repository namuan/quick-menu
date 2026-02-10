import Foundation

class Logger {
    static let shared = Logger()
    
    private let logDirectory: URL
    private let logFile: URL
    private let maxLogSize: Int = 1024 * 1024 // 1MB
    private let maxLogFiles: Int = 5
    
    private let dateFormatter: DateFormatter
    private let fileManager = FileManager.default
    
    private init() {
        // Standard macOS log location: ~/Library/Logs/QuickMenu/
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        logDirectory = libraryURL.appendingPathComponent("Logs/QuickMenu", isDirectory: true)
        logFile = logDirectory.appendingPathComponent("quickmenu.log")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        createLogDirectory()
        rotateLogsIfNeeded()
    }
    
    private func createLogDirectory() {
        do {
            try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create log directory: \(error)")
        }
    }
    
    private func rotateLogsIfNeeded() {
        guard fileManager.fileExists(atPath: logFile.path) else { return }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: logFile.path)
            if let fileSize = attributes[.size] as? Int, fileSize > maxLogSize {
                rotateLogs()
            }
        } catch {
            print("Failed to check log file size: \(error)")
        }
    }
    
    private func rotateLogs() {
        // Remove oldest log file
        let oldestLog = logDirectory.appendingPathComponent("quickmenu.\(maxLogFiles).log")
        if fileManager.fileExists(atPath: oldestLog.path) {
            try? fileManager.removeItem(at: oldestLog)
        }
        
        // Shift existing log files
        for i in (1..<maxLogFiles).reversed() {
            let oldFile = logDirectory.appendingPathComponent("quickmenu.\(i).log")
            let newFile = logDirectory.appendingPathComponent("quickmenu.\(i + 1).log")
            
            if fileManager.fileExists(atPath: oldFile.path) {
                try? fileManager.moveItem(at: oldFile, to: newFile)
            }
        }
        
        // Move current log to .1
        let rotatedLog = logDirectory.appendingPathComponent("quickmenu.1.log")
        try? fileManager.moveItem(at: logFile, to: rotatedLog)
    }
    
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let filename = (file as NSString).lastPathComponent
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(filename):\(line)] \(function): \(message)\n"
        
        // Print to console
        print(logMessage, terminator: "")
        
        // Write to file
        if let data = logMessage.data(using: .utf8) {
            if fileManager.fileExists(atPath: logFile.path) {
                // Append to existing file
                if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                    _ = fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                    
                    // Check if we need to rotate after writing
                    rotateLogsIfNeeded()
                }
            } else {
                // Create new file
                try? data.write(to: logFile)
            }
        }
    }
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    var logFilePath: String {
        return logFile.path
    }
}

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}
