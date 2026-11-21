import DoctorLibrary

/// The shared library models under names that can't collide with anything the
/// SDK exports (SwiftUI/Foundation have their own `Document` on recent SDKs).
typealias LibraryDocument = DoctorLibrary.Document
typealias LibraryFolder = DoctorLibrary.Folder
