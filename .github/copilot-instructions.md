# Omnicit.PIM Copilot Instructions

The rules for this repository live in [CLAUDE.md](../CLAUDE.md) at the repository root, and must be
read before making any change. It is their single owner -- the branch policy, building, testing and
publishing, the CHANGELOG and version model, the authentication architecture, and the code,
error-handling, test and security conventions -- and this file does not restate any of them.

The sections most relevant to an assistant:

- **Branch Policy -- ALWAYS CHECK FIRST** -- which branch to work on, and what a pull request needs
  before it can merge to `main`.
- **Build and Test Commands** -- how to bootstrap, build and run the full test suite.
- **Error Handling** -- how public and private functions report errors.
- **Testing Conventions** -- how unit tests import the module and what they mock.
- **SECURITY (Hard Rules - High Privilege)** -- what may never happen, in code, in tests or in a
  live session.
