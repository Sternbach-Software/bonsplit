import Foundation
// TEMPORARY PROBE for CMUXTERM-MACOS-41NN; not for merge.
enum ProbeCounters {
    nonisolated(unsafe) static var tabItemBody = 0
    nonisolated(unsafe) static var tabBarBody = 0
    nonisolated(unsafe) static var tabBarInit = 0
    nonisolated(unsafe) static var paneBody = 0
    nonisolated(unsafe) static var monitorInit = 0
    static func reset() { tabItemBody = 0; tabBarBody = 0; tabBarInit = 0; paneBody = 0; monitorInit = 0 }
    static var summary: String { "tabItemBody=\(tabItemBody) tabBarBody=\(tabBarBody) tabBarInit=\(tabBarInit) paneBody=\(paneBody) monitorInit=\(monitorInit)" }
}
