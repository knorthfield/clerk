#!/bin/zsh
# Generates the project and runs the tests. Prints only errors and test results.
cd "${0:A:h}"
xcodegen generate --quiet
xcodebuild test -scheme Clerk -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages 2>&1 |
  grep -E "error:|✘|✔ Test run|\*\* TEST"
