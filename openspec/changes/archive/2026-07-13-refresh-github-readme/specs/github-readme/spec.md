## ADDED Requirements

### Requirement: Evidence-backed public overview

The root README SHALL describe Hype’s current identity, implemented capabilities, architecture, and limitations using claims traceable to the final repository state or clearly attributed dated evidence.

#### Scenario: Reader evaluates current functionality
- **GIVEN** a reader opens the repository root on GitHub
- **WHEN** they read a capability or compatibility statement
- **THEN** the statement reflects current implementation evidence
- **AND** any opt-in, target-specific, incomplete, or unsupported boundary is stated without requiring the reader to infer it

#### Scenario: Volatile metric is presented
- **GIVEN** the README includes a count, percentage, leaderboard, or “current/latest” assertion
- **WHEN** that claim is reviewed
- **THEN** it is mechanically reproducible from the repository or attributed to a dated checked-in result
- **AND** observed outcomes are not conflated with modeled probabilities

### Requirement: Reproducible onboarding

The root README SHALL provide copyable prerequisites, build, run, install, and test guidance that matches files, products, platforms, and command options in the final repository tree.

#### Scenario: Developer starts from a clean checkout
- **GIVEN** a supported macOS development environment and a clean checkout
- **WHEN** the developer follows the README quick start
- **THEN** every referenced command and path exists
- **AND** baseline build/test/authoring steps do not require an optional hosted AI or media-generation provider

#### Scenario: Optional integration is configured
- **GIVEN** a developer chooses Ollama, an OpenAI-compatible endpoint, OpenAI, Meshy, or MCP/debug automation
- **WHEN** they read the relevant README guidance
- **THEN** the text identifies whether the integration is local or network-backed
- **AND** accurately describes opt-in, credentials, egress, privilege, and stack-level gates that apply

### Requirement: Safe compatibility description

The root README SHALL state that HyperCard import treats legacy input as untrusted data and SHALL NOT imply that Hype executes legacy native XCMD/XFCN code.

#### Scenario: User considers importing a classic stack
- **GIVEN** a user reads about HyperCard import
- **WHEN** compatibility behavior is described
- **THEN** structural conversion and supported Swift emulation are distinguished from native legacy-code execution
- **AND** limitations direct the user to the current compatibility documentation

### Requirement: GitHub-native navigation

The root README SHALL render coherently on GitHub and link to existing repository resources with portable relative Markdown links.

#### Scenario: Reader follows documentation links
- **GIVEN** the README is rendered from the GitHub default branch
- **WHEN** the reader follows a repository documentation link
- **THEN** the target exists at the final commit
- **AND** no link depends on a developer-specific absolute filesystem path

### Requirement: Honest verification and publication

The completed documentation change SHALL be verified through the active MPD and git gates and SHALL be published only after the staged content and actual GitHub rendering are checked.

#### Scenario: Maintainer declares the refresh complete
- **GIVEN** the README rewrite is ready to publish
- **WHEN** completion is reported
- **THEN** the required MPD gates and configured hooks have passed without bypass
- **AND** local `main`, `origin/main`, and GitHub’s default branch identify the same commit
- **AND** the README has been inspected on the actual GitHub repository page
