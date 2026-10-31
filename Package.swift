// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CommentaryBoost",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "commentary-boost",
            path: "Sources/CommentaryBoost",
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed an Info.plist so macOS can show the "System Audio Recording" permission prompt.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist", "-Xlinker", "Sources/CommentaryBoost/Info.plist",
                ]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
