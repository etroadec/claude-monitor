import Foundation

func debugLog(_ msg: String) {
    let str = "\(Date()): \(msg)\n"
    let path = "/tmp/claude-monitor-debug.log"
    if let data = str.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: path) {
            let handle = FileHandle(forWritingAtPath: path)!
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}
