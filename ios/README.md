# VetMate iOS development preview

This branch does not change the deployed GitHub Pages website.

The first iOS proof of concept bundles the existing V2.2 web application and adds a native SwiftUI / Apple Vision label-scanning screen with camera and photo picker. It is not a complete native rewrite or a clinically validated app. The browser-based breed recognition still requires external model downloads. Records local to the website do not automatically migrate to this app; secure clinical storage and Face ID are not yet implemented.

## Build on macOS
Install Xcode and XcodeGen, copy the root index.html and vetmate-hero-v22.js into ios/Web, then run xcodegen within ios. Build the generated VetMate project for an iOS simulator. No signing secrets are required for a simulator build.

TestFlight requires a separately signed archive, an appropriate Apple distribution certificate and provisioning profile, app icon and privacy checks. The existing App Store Connect Developer key is intended for uploading, not a substitute for signing credentials. Never commit private keys. Public repository collaborators and workflows must be trusted before any secrets are made available.

Use fictional data only. Review all calculation formulas, OCR accuracy and medication/health references with a veterinary professional before clinical use.
