import DoctorLibrary

/// The shared library models, re-declared at module scope so they win over
/// any same-named type the SDK exports. `Document` used to be defined in this
/// module, which is what made the bare name unambiguous; now that it lives in
/// `DoctorLibrary`, this keeps every `Document` in the app meaning ours.
typealias Document = DoctorLibrary.Document
typealias Folder = DoctorLibrary.Folder
