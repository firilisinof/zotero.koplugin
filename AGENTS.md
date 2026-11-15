# LLM contribution instructions

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing the project.

## Changes

- Check the branch against the remote before editing. Preserve local work and
  reconcile upstream changes before rewriting shared documentation.
- Metadata browsing and notes are read-only. Position sharing and highlight sync
  are independent, opt-in features and must remain off by default.
- Keep document bytes, unrelated sidecar data and reader settings unchanged. Highlight
  imports may update only the corresponding annotations.
- Automatic operations must never prompt to enable Wi-Fi.
- Reject unsupported positions and highlight ranges with an explanation.
  Do not approximate them.
- Use fixture data and temporary profiles for tests. Live writes require
  disposable attachments.
- Run the relevant checks from CONTRIBUTING.md and report the results.

## Documentation

- Keep user help in `docs/`, contributor guidance in `CONTRIBUTING.md`, and
  agent instructions here. Keep `CLAUDE.md` as a pointer to this file.
- Write concise, plain US English. Assume readers know the tools they use.
  Omit routine explanations, repeated caveats and generic reminders.
- Update the existing explanation instead of adding a duplicate summary.
  Document current behavior, not completed plans or task history.
- Verify commands and behavior against the project. Use relative links to
  repository files. Do not depend on private notes or machine-specific paths.
- Add roadmap items only when requested.
