# Local validation

Requires Xcode with the macOS SDK and permission for XCTest to control the test app.
Run from this repository with an idle desktop; the UI suite drives the pointer and keyboard.

```bash
./scripts/test-e2e.sh
```

The script runs all unit/integration tests and all UI tests serially, with code coverage enabled.
It retains the `.xcresult` bundles, exports and merges the `xccov` archives, and checks **at least
80% of every executable line in `Chowser.app`**, including UI and system adapters. There are no
file exclusions. Counts from test bundles do not contribute to this target's denominator.
Set `CHOWSER_TEST_RESULTS` to a new output directory to choose where evidence is kept.

To check an already merged report:

```bash
xcrun xccov view --report --json /path/to/merged.xccovreport > /tmp/chowser-coverage.json
xcrun python3 scripts/check-code-coverage.py /tmp/chowser-coverage.json
xcrun python3 -B -m unittest discover -s scripts/tests -p 'test_code_coverage.py'
```

The runner uses Xcode’s Python via `xcrun`, so an incompatible Python earlier on `PATH` cannot bypass the gate.

The gate rejects missing, ambiguous or empty application targets. It compares integer counts,
so a displayed rounded value of 80.00% can still fail if the actual ratio is below 80%.
Merge only archives produced from the same application sources.

## Isolation and assertions

- Unit tests use process-specific preferences, history and log paths. HTTP integration tests
  bind only loopback and stop their listeners. Launch adapter tests use nonexistent app paths.
- UI launches use a new preferences suite and a temporary activity/log directory. External
  browser opens and default-browser integration are disabled. A successful synthetic open
  publishes an atomic counter at the completion boundary; assertions also check order and
  history for URL batches.
- The UI runner launches the adjacent built application by file URL and verifies the running
  bundle's resolved path. Another build registered with the same bundle ID cannot silently
  become the application under test. Failure diagnostics capture only the test app's windows.
- Signed catalog and native consent fixtures exist only in Debug builds, require explicit
  UI-testing flags, use a fresh in-memory signing key and pass through the normal verifier.
  They do not change the production keyring or download catalogs.
- Regression scenarios cover keyboard and drag selection, failed browser launch, two successive
  choices from one incoming batch, rule-form typing, validation, source-app conditions, catalog
  consent, Undo, reset and both explicit App Mode choices.
- Tests do not install the app, publish a release, or change the Mac's default browser.

Release build and artifact checks for both distribution variants are documented in
[DISTRIBUTION.md](DISTRIBUTION.md). Build each in a separate DerivedData directory.
