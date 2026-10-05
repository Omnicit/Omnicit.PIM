# Security Policy

## Why this matters

`Omnicit.PIM` activates and deactivates privileged Microsoft Entra ID directory roles, Azure
resource roles and PIM for Groups memberships for the signed-in user. Used as intended, it
raises that user's privilege for a requested duration, in the tenant they signed in to. A
vulnerability here -- a bug that activates more than was asked (another role, a wider scope,
another group or access type, a longer duration), that acts in the wrong tenant, or that leaks a
token -- is a privilege-escalation vulnerability, not an ordinary bug.

## Reporting a vulnerability

**Do not open a public GitHub issue with the details of a security vulnerability.**

Private vulnerability reporting is not switched on for this repository yet, so there is no private
form to point you at. Until it is, open an issue that asks for a private contact for a security
report, and put no detail in it: no cmdlet name, no reproduction steps, no output -- only that you
have a security report and need a private way to send it. The maintainers will answer in that issue
with a way to send the details privately. Send nothing until a repository maintainer -- an account
shown with the Member, Owner or Collaborator badge on this repository -- answers in that issue, and
ignore a contact or link offered by anyone else. This section is updated when private reporting is
switched on. No response-time commitment is made.

## What to include

Send these through the private contact, never in the public issue.

- The cmdlet(s) or code path involved, and the module version or commit you tested against.
- Steps to reproduce, and what you expected versus what actually happened.
- The impact: what could an attacker do with it (for example: activate a role, scope or group the
  user did not ask for, act against another tenant, read a token, or bypass a
  `ShouldProcess`/`-WhatIf` guard).

## What never to include, in a report or anywhere else

- No access tokens, refresh tokens, `Authorization` headers or client secrets.
- No unredacted console output. A raw error record from a failed Graph request carries the bearer
  token in plain text inside its request message -- do not paste one.
- **Tenant ids, subscription ids and object ids are identifiers, not credentials.** They are not
  rotated, and disclosing one is not itself a credential compromise. They are still treated as
  sensitive, because they are correlatable to a real tenant, so redact them in a report and use
  placeholders such as `contoso` -- but including one does not require the rotation a leaked token
  or secret would.

## Supported versions

The newest stable release is `0.5.1`, published on 2026-05-29, and the built version is held in
the `0.x` line (see `CLAUDE.md` "CHANGELOG and Version"). Only the current `main` branch is
supported; there are no maintained release branches to backport a fix to.

Every merge to `main` also publishes a preview version to the PowerShell Gallery. A preview has
passed the same full test suite on Linux, Windows and macOS as a stable release, but a fix is
considered released when it reaches a stable version; previews exist so the current state of `main`
is installable, not as a support channel of their own.
