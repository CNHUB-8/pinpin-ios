# Core tests

`BeadStudioCoreTests.swift` is an XCTest file for the `BeadStudio` iOS app module.
Tests cover model bounds and completion validation, palette validation, known CIE Lab
reference values, transparency/unpremultiplication, pixel order, mirrored UIImage
orientation, the maximum-color limit, persistence roundtrip, deletion, corrupt input,
and memory-state preservation after a failed write.

Run the project's test scheme on a Mac with Xcode and an iOS simulator. These tests
were authored and statically reviewed on Windows; they have **not** been compiled or
executed in Xcode here. The image algorithm is an independent implementation and is
not claimed to reproduce the original Android app pixel-for-pixel.
