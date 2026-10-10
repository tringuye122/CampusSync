#!/bin/bash
# Runs the app's Firebase integration tests against the LOCAL emulators.
# Nothing here touches the real Firebase project.
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${1:-platform=iOS Simulator,name=iPhone 15 Pro}"

npx firebase emulators:exec --only auth,firestore --project campussync-780a5 \
  "cd ../CampusSync && TEST_RUNNER_FIREBASE_EMULATOR_HOST=localhost xcodebuild test \
     -scheme CampusSync -destination '$DEVICE' -only-testing:CampusSyncTests/FirebaseIntegrationTests"
