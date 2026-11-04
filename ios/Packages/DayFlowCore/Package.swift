// swift-tools-version:5.9
// DayFlowCore: the parts of DayFlow that don't depend on iOS. The data model, the rules that
// clean data, the reminder planner, and export and import. They match the Mac app's src/main.js,
// so files and reminders behave the same on both. Tested on the Mac with `swift test`.
import PackageDescription

let package = Package(
    name: "DayFlowCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DayFlowCore", targets: ["DayFlowCore"])],
    targets: [
        .target(name: "DayFlowCore"),
        .testTarget(name: "DayFlowCoreTests", dependencies: ["DayFlowCore"]),
    ]
)
