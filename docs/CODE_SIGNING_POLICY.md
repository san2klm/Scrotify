# Code signing policy

*Política de firma de código (en inglés porque la revisa SignPath Foundation).
Detalle técnico en español: `docs/SIGNING.md`.*

Windows: free code signing provided by [SignPath.io](https://about.signpath.io/),
certificate by [SignPath Foundation](https://signpath.org/).
*(Applies once the SignPath Foundation application is approved; until then
Windows builds are unsigned and verified with the minisign-signed
`SHA256SUMS`.)*

## What is signed

Only binaries built by the project's CI (GitHub Actions) from the source code
in <https://github.com/Dante0Q/CrotoWave>:

| Platform | Signature |
|---|---|
| Windows (`CrotoWave-Setup-<version>.exe`, `CrotoWave.exe`) | Authenticode via SignPath Foundation |
| Android (APK) | the project's own key, SHA-256 `06:37:E6:E7:6D:F2:E7:8D:3B:C8:3F:70:F3:CD:48:BA:CC:B2:2A:52:D9:5C:EE:93:91:67:5C:9B:BD:3B:4F:7D` |
| All release files | `SHA256SUMS` signed with minisign; public key `crotowave-release.pub` |

Third-party components shipped with the Windows build (libmpv, FFmpeg) are
upstream open source binaries and are not signed by this project.

## Team roles

| Role | Members |
|---|---|
| Committers and reviewers | [Dante0Q](https://github.com/Dante0Q) |
| Approvers | [Dante0Q](https://github.com/Dante0Q) |

Contributions from people outside this list are reviewed by a committer
before they are merged. Every signing request is approved manually by an
approver. All members use multi-factor authentication on GitHub and SignPath.

## Privacy

CrotoWave has no telemetry, analytics or ads. Every network connection it
makes, and when, is listed in the privacy policy: [`PRIVACY.md`](../PRIVACY.md).
