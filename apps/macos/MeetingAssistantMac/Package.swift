// swift-tools-version: 5.9
import PackageDescription
import Foundation

let environment = ProcessInfo.processInfo.environment
let useRustFFI = environment["MEETING_USE_RUST_FFI"] == "1"
let rustLibSearchPath = environment["MEETING_RUST_FFI_LIB_DIR"] ?? "./Vendor/meeting_core_ffi/lib"
let rustStaticLibPath = environment["MEETING_RUST_FFI_STATIC_LIB"] ?? "\(rustLibSearchPath)/libmeeting_core_ffi.a"

let package = Package(
    name: "MeetingAssistantMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MeetingAssistantMac", targets: ["MeetingAssistantMac"])
    ],
    targets: [
        .target(
            name: "CMeetingCoreFFI",
            path: "Sources/CMeetingCoreFFI",
            publicHeadersPath: "include",
            cSettings: useRustFFI ? [
                .define("MEETING_USE_RUST_FFI")
            ] : []
        ),
        .target(
            name: "CoreBridge",
            dependencies: ["CMeetingCoreFFI"],
            path: "Sources/CoreBridge",
            linkerSettings: useRustFFI ? [
                // Force static archive link to avoid runtime dylib lookup failures in Xcode Run.
                .unsafeFlags(["-Xlinker", "-force_load", "-Xlinker", rustStaticLibPath])
            ] : []
        ),
        .executableTarget(
            name: "MeetingAssistantMac",
            dependencies: ["CoreBridge"],
            path: "Sources/MeetingAssistantMac",
            resources: [
                .process("Resources"),
            ]
        )
    ]
)
