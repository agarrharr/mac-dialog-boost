// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDialogBoost",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "mac-dialog-boost",
            path: "Sources/MacDialogBoost",
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed an Info.plist so macOS can show the "System Audio Recording" permission prompt.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist", "-Xlinker", "Sources/MacDialogBoost/Info.plist",
                ]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
