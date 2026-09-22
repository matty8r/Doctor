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
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DoctorMarkdown", targets: ["DoctorMarkdown"])
    ],
    targets: [
        .target(
            name: "DoctorMarkdown",
            path: "Sources/DoctorMarkdown"
        ),
        .executableTarget(
            name: "Doctor",
            dependencies: ["DoctorMarkdown"],
            path: "Sources/Doctor"
        ),
        .testTarget(
            name: "DoctorMarkdownTests",
            dependencies: ["DoctorMarkdown"],
            path: "Tests/DoctorMarkdownTests"
        )
    ]
)
