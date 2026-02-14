//
//  LogStore.swift
//  Soluna
//

import Foundation
import Observation

/// 日志类型。
enum LogChannel {
    case system
    case download
}

/// 统一的日志存储。
@MainActor
@Observable
final class LogStore {
    private(set) var systemLog: String = ""
    private(set) var downloadLog: String = ""

    func append(_ message: String, channel: LogChannel) {
        let line = "[\(timestamp())] \(message)"
        switch channel {
        case .system:
            appendLine(line, to: &systemLog)
        case .download:
            appendLine(line, to: &downloadLog)
        }
    }

    func clear(channel: LogChannel) {
        switch channel {
        case .system:
            systemLog = ""
        case .download:
            downloadLog = ""
        }
    }

    private func appendLine(_ line: String, to log: inout String) {
        if log.isEmpty {
            log = line
        } else {
            log.append("\n\(line)")
        }
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
