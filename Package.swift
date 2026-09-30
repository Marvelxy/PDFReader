// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PDFReader",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .target(
            name: "PDFReaderKit",
            path: "Sources/PDFReaderKit",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "PDFReader",
            dependencies: ["PDFReaderKit"],
            path: "Sources/PDFReader",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "PDFReaderVerify",
            dependencies: ["PDFReaderKit"],
            path: "Sources/PDFReaderVerify",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "PDFReaderKitTests",
            dependencies: ["PDFReaderKit"],
            path: "Tests/PDFReaderKitTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
