# Changelog for Omnicit.PIM

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added Pester unit tests for all six `IArgumentCompleter` classes (`AzureActivatedRoleCompleter`, `AzureEligibleRoleCompleter`, `DirectoryActivatedRoleCompleter`, `DirectoryEligibleRoleCompleter`, `GroupActivatedCompleter`, `GroupEligibleCompleter`) to cover `CompleteArgument` happy-path, scope-name, filter, and catch-path branches.
- Added missing error-branch tests in `Convert-GraphHttpException`, `Disable-OPIMEntraIDGroup`, `Enable-OPIMAzureRole`, `Enable-OPIMDirectoryRole`, and `Enable-OPIMEntraIDGroup` to raise code coverage above the 85% threshold (was 77.28%, now 89.95%).

### Changed

- For changes in existing functionality.

### Deprecated

- For soon-to-be removed features.

### Removed

- For now removed features.

### Fixed

- For any bug fix.

### Security

- In case of vulnerabilities.

