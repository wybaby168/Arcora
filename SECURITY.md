# Security policy

## Reporting a vulnerability

Use GitHub's [private vulnerability reporting](https://github.com/wybaby168/Arcora/security/advisories/new) for suspected security issues. Do not disclose an exploit, sensitive archive, password or RAR registration key in a public issue. If the private channel is unavailable, open an issue asking for a private contact method without disclosing the vulnerability.

Include the affected revision, macOS and engine versions, architecture, target filesystem, expected behavior and a minimal synthetic reproduction. Do not run hostile samples outside a suitable isolated environment.

## Scope and maintenance

This is an early open-source project. Security fixes target the current default branch; there is no promised maintenance period for older snapshots or response-time SLA. Source availability and passing tests are not a security certification.

Native codecs are separate processes but are not confined by a strong App Sandbox boundary. The app rejects unsafe archive entries and audits output; unknown engine vulnerabilities and resource exhaustion remain possible. See the [security design and residual risks](Documentation/SECURITY.md).

## Private material and builds

Never publish RAR encoders, original RAR packages, registration files, signing keys, application-data directories or local evaluation apps in this repository, issue attachments, CI artifacts or releases. Public builds must pass the source-tree and distribution checks. Report an accidental exposure privately and rotate affected credentials as appropriate; removing a file in a later commit does not remove it from history.
