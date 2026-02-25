import Foundation

final class Logger {
    static let shared = Logger()
    
    private let logDirectory: URL
    private let logFile: URL
    private let maxLogSize: Int64 = 1024 * 1024 // 1MB
    private let maxLogFiles: Int = 5
    
    private let dateFormatter: DateFormatter
    private let fileManager = FileManager.default
    private let logQueue = DispatchQueue(label: "com.namuan.quickmenu.logger", qos: .utility)
    private let appName: String
    
    private init() {
        let bundleAppName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        appName = (bundleAppName?.isEmpty == false ? bundleAppName! : "QuickMenu").replacingOccurrences(of: "/", with: "-")

        // Standard macOS log location: ~/Library/Logs/<AppName>/
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        logDirectory = libraryURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)

        let logBaseName = appName.lowercased().replacingOccurrences(of: " ", with: "-")
        logFile = logDirectory.appendingPathComponent("\(logBaseName).log")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        ensureLogDirectoryExists()
        ensureLogFileExists()
        rotateLogsIfNeeded()
    }
    
    private func ensureLogDirectoryExists() {
        do {
            try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create log directory: \(error)")
        }
    }

    private func ensureLogFileExists() {
        guard !fileManager.fileExists(atPath: logFile.path) else {
            return
        }

        let initialLine = "[\(dateFormatter.string(from: Date()))] [INFO] Logger initialized for \(appName)\n"
        do {
            try initialLine.data(using: .utf8)?.write(to: logFile)
        } catch {
            print("Failed to create log file: \(error)")
        }
    }
    
    private func rotateLogsIfNeeded() {
        guard fileManager.fileExists(atPath: logFile.path) else { return }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: logFile.path)
            if let fileSize = attributes[.size] as? NSNumber,
               fileSize.int64Value > maxLogSize {
                rotateLogs()
            }
        } catch {
            print("Failed to check log file size: \(error)")
        }
    }
    
    private func rotateLogs() {
        let baseName = logFile.deletingPathExtension().lastPathComponent
        let fileExtension = logFile.pathExtension

        // Remove oldest log file
        let oldestLog = logDirectory.appendingPathComponent("\(baseName).\(maxLogFiles).\(fileExtension)")
        if fileManager.fileExists(atPath: oldestLog.path) {
            do {
                try fileManager.removeItem(at: oldestLog)
            } catch {
                print("Failed to remove oldest log file: \(error)")
            }
        }
        
        // Shift existing log files
        for i in (1..<maxLogFiles).reversed() {
            let oldFile = logDirectory.appendingPathComponent("\(baseName).\(i).\(fileExtension)")
            let newFile = logDirectory.appendingPathComponent("\(baseName).\(i + 1).\(fileExtension)")
            
            if fileManager.fileExists(atPath: oldFile.path) {
                do {
                    if fileManager.fileExists(atPath: newFile.path) {
                        try fileManager.removeItem(at: newFile)
                    }
                    try fileManager.moveItem(at: oldFile, to: newFile)
                } catch {
                    print("Failed rotating \(oldFile.lastPathComponent): \(error)")
                }
            }
        }
        
        // Move current log to .1
        let rotatedLog = logDirectory.appendingPathComponent("\(baseName).1.\(fileExtension)")
        do {
            if fileManager.fileExists(atPath: rotatedLog.path) {
                try fileManager.removeItem(at: rotatedLog)
            }
            try fileManager.moveItem(at: logFile, to: rotatedLog)
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        } catch {
            print("Failed to rotate active log file: \(error)")
        }
    }
    
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        logQueue.async {
            let timestamp = self.dateFormatter.string(from: Date())
            let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(filename):\(line)] \(function): \(message)\n"

            // Print to console
            print(logMessage, terminator: "")

            self.ensureLogDirectoryExists()
            self.ensureLogFileExists()

            guard let data = logMessage.data(using: .utf8) else {
                return
            }

            do {
                self.rotateLogsIfNeeded()

                let fileHandle = try FileHandle(forWritingTo: self.logFile)
                defer {
                    try? fileHandle.close()
                }

                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: data)
                self.rotateLogsIfNeeded()
            } catch {
                print("Failed to write log entry: \(error)")
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
