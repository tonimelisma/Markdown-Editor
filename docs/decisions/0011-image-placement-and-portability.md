# ADR-0011 — Copy added images into a shared sibling assets directory

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Toni Melisma
- **Related:** REQ-060–REQ-077; INC-03; [VISION §5](../VISION.md);
  [RESEARCH-0004](../research/0004-inc03-image-assets-and-portability.md);
  correction [ADR-0012](0012-transactional-descriptor-relative-image-placement.md)

## Context

Pasting or dropping an image must produce ordinary Markdown and usable companion files without
creating an app-specific document package. A loose Markdown file has no standardized attachment
directory or atomic relationship with sibling files. File URLs, file promises, and clipboard
bitmaps also have different lifecycles and failure modes.

The design must balance portability, native Mac formats, minimal prompts, deterministic naming,
Save As behavior, undo, accessibility, hostile inputs, and partial I/O failure.

## Decision

When a user pastes or drops a supported image into a **saved** Markdown document:

1. Place it in a visible sibling directory named `assets/`.
2. Treat that directory as shared and non-owned; never delete or overwrite existing contents.
3. Accept file-backed PNG, JPEG, GIF, HEIC, and HEIF and copy their bytes unchanged. Do not
   transcode HEIC/HEIF. Encode bitmap-only clipboard content as PNG.
4. Validate the detected image representation rather than trusting the extension or provider
   filename.
5. Generate a lowercase portable ASCII basename. Reuse an existing destination only when its
   bytes are identical; otherwise append a deterministic SHA-256 prefix, extending it if needed.
   Resolve collisions case-insensitively.
6. Insert only standard relative source such as `![](assets/photo.heic)`, after every destination
   for the user action exists. Do not emit a title, dimensions, raw HTML, base64, percent-encoded
   filename, or app metadata.
7. Use an empty image description, selecting it for immediate editing after a single addition.
   Never substitute a filename for meaningful alternative text.
8. Treat a multi-image action as one transaction and one source undo operation. Undo and
   reference deletion never remove assets.
9. Require an untitled document to be saved before placement. Save As or a move does not
   silently relocate assets; warn non-destructively when generated relative references become
   unresolved after the parent directory changes.
10. Reject directories, packages, aliases, symlinks, a symlinked `assets/` destination, and any
    generated path that fails a resolved-containment check.

There is no “Import” document command. “Add image” is the user concept; copying a file into
`assets/` is an internal consequence of paste, drag-and-drop, or the approved INC-04
“Add Image…” file picker. All three use one placement transaction.

## Consequences

- **Positive:** no private format or hidden state; common inputs work without configuration;
  native HEIC/HEIF bytes and metadata are preserved; collisions and failures are deterministic
  and non-destructive.
- **Negative:** HEIC/HEIF references use standard Markdown syntax but will not render in every
  non-Apple viewer. A shared `assets/` directory does not establish ownership. Moving only the
  Markdown file can break relative references. Undo can leave an unreferenced asset.
- **Follow-ups:** a future explicit “Save a Copy with Assets” or cleanup command requires its own
  lifecycle design. Image sizing and remote downloads remain out of scope.
- **Implementation correction:** INC-03 did not satisfy the transaction, promise, lifecycle, and
  containment mechanics required by this decision. ADR-0012 and PLAN-0005 propose replacing that
  implementation without changing this user-visible policy.

## Alternatives considered

- **`<document-stem>.assets/`:** clearer apparent ownership, but renaming the Markdown file makes
  the convention stale and encourages unsafe ownership assumptions.
- **Document package:** atomic but violates the ordinary loose `.md` requirement.
- **Embed base64:** self-contained but bloats and obscures source and reduces compatibility.
- **Reference original absolute path:** avoids copying but is nonportable and may expose local
  filesystem details.
- **Convert HEIC/HEIF to JPEG:** rejected explicitly; it changes bytes and can lose metadata,
  HDR, depth, animation, color, or quality.
- **Preserve arbitrary provider filenames:** rejected because reserved names, Unicode
  normalization, spaces, punctuation, case collisions, and Markdown escaping reduce portability.
- **Delete assets on undo:** rejected because text undo cannot safely establish file ownership.
