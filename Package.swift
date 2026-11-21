// swift-tools-version:5.9
import PackageDescription

// Doctor is deliberately dependency-free: everything it needs (Markdown parsing,
// rendering, PDF output) is either in this package or in a system framework.
// That keeps `swift build` offline and the app bundle small.
//
// The Markdown engine lives in its own target so it can be tested without
// launching an app — it's the part most likely to be wrong, and the part where
// being wrong quietly damages someone's file.
let package = Package(
    name: "Doctor",
    // iOS is here so the iOS app (../iOS) can depend on DoctorEditorKit as a
    // local package — it never affects `swift build` on this Mac, which only
    // ever builds the macOS products. The `Doctor` executable target below
    // stays macOS-only in practice: it imports AppKit, so it simply won't
    // compile if anything ever tried to build it for iOS.
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DoctorMarkdown", targets: ["DoctorMarkdown"]),
        .library(name: "DoctorEditorKit", targets: ["DoctorEditorKit"]),
        .library(name: "DoctorLibrary", targets: ["DoctorLibrary"])
    ],
    targets: [
        .target(
            name: "DoctorMarkdown",
            path: "Sources/DoctorMarkdown"
        ),
        // The rendering engine shared with iOS: theme, syntax highlighter,
        // table layout, and the layout manager that does concealment. See
        // docs/ios.md for which of Doctor's pieces this covers and why.
        .target(
            name: "DoctorEditorKit",
            dependencies: ["DoctorMarkdown"],
            path: "Sources/DoctorEditorKit"
        ),
        // The synced library — the SwiftData/CloudKit `Document` and `Folder`
        // models and the store that opens them. Shared by the iOS and macOS
        // apps so both read the one CloudKit schema and can't drift apart.
        .target(
            name: "DoctorLibrary",
            path: "Sources/DoctorLibrary"
        ),
        .executableTarget(
            name: "Doctor",
            dependencies: ["DoctorMarkdown", "DoctorEditorKit", "DoctorLibrary"],
            path: "Sources/Doctor"
        ),
        .testTarget(
            name: "DoctorLibraryTests",
            dependencies: ["DoctorLibrary"],
            path: "Tests/DoctorLibraryTests"
        ),
        .testTarget(
            name: "DoctorMarkdownTests",
            dependencies: ["DoctorMarkdown"],
            path: "Tests/DoctorMarkdownTests"
        )
    ]
)
