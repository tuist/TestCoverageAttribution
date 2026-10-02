# Security Policy

## Supported versions

TestCoverageAttribution is experimental. Security fixes land on `main` and in the next release; older releases don't get patches.

## Reporting a vulnerability

Report vulnerabilities privately through [GitHub's private vulnerability reporting](https://github.com/tuist/TestCoverageAttribution/security/advisories/new). Don't open a public issue.

Include what you found, how to reproduce it, and which version or commit you used. We'll acknowledge the report, keep you updated while we work on a fix, and credit you in the advisory unless you'd rather stay anonymous. Please give us reasonable time to release a fix before you disclose the issue publicly.

## Scope

The package runs inside test processes that link it. It reads coverage counters, writes files under `$TEST_COVERAGE_ATTRIBUTION_DIR`, and reads `TEST_COVERAGE_ATTRIBUTION_OWNER` from the environment. Reports about how it handles those files and variables, or anything that lets it crash, hang, or corrupt the test process, are in scope.
