#!/usr/bin/env bash
set -euo pipefail

PROJECT="Chowser.xcodeproj"
DESTINATION="platform=macOS"
test_results="${CHOWSER_TEST_RESULTS:-$(mktemp -d "${TMPDIR:-/tmp}/chowser-validation.XXXXXX")}"
mkdir -p "$test_results"
signing=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual)
echo "Results: $test_results"

echo "Running unit tests..."
xcodebuild test \
  -project "$PROJECT" \
  -scheme Chowser-osp \
  -destination "$DESTINATION" \
  -derivedDataPath "$test_results/unit-build" \
  -resultBundlePath "$test_results/unit.xcresult" \
  -enableCodeCoverage YES -parallel-testing-enabled NO \
  -only-testing:ChowserTests "${signing[@]}"

echo "Running UI end-to-end tests..."
xcodebuild test \
  -project "$PROJECT" \
  -scheme ChowserUITests \
  -destination "$DESTINATION" \
  -derivedDataPath "$test_results/ui-build" \
  -resultBundlePath "$test_results/ui.xcresult" \
  -enableCodeCoverage YES -parallel-testing-enabled NO "${signing[@]}"

for suite in unit ui; do
  xcrun xcresulttool export coverage --path "$test_results/$suite.xcresult" \
    --output-path "$test_results/$suite-coverage"
done
shopt -s nullglob
unit_reports=("$test_results/unit-coverage/"*CoverageReport)
unit_archives=("$test_results/unit-coverage/"*CoverageArchive)
ui_reports=("$test_results/ui-coverage/"*CoverageReport)
ui_archives=("$test_results/ui-coverage/"*CoverageArchive)
if [[ ${#unit_reports[@]} -ne 1 || ${#unit_archives[@]} -ne 1 || ${#ui_reports[@]} -ne 1 || ${#ui_archives[@]} -ne 1 ]]; then
  echo "Expected one coverage report and archive per suite" >&2
  exit 1
fi
xcrun xccov merge --outReport "$test_results/merged.xccovreport" --outArchive "$test_results/merged.xccovarchive" \
  "${unit_reports[0]}" "${unit_archives[0]}" "${ui_reports[0]}" "${ui_archives[0]}"
xcrun xccov view --report --json "$test_results/merged.xccovreport" > "$test_results/coverage.json"
xcrun python3 scripts/check-code-coverage.py "$test_results/coverage.json"
echo "All tests and the whole-application coverage gate passed."
