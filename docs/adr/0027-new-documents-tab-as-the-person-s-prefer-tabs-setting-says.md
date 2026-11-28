# 0027. New documents tab as the person's Prefer tabs setting says

- Status: accepted
- Date: 2026-11-27

## Context and problem

**Why.** COR-53 set `.preferred`, which overrides that setting and puts every new document into a
tab, without a reason recorded. The app was to behave "just like TextEdit", and
TextEdit follows the setting. A profile of three warm ⌘N opens (probe 46014139254, Debug) also
put 79 of the 143 samples of showing a window in AppKit merging it into the tab group and laying
it out again for the tab bar.

## Decision drivers

**Criteria:** standard macOS behaviour (vision.md objective 4, "No surprises"); the instruction to
behave like TextEdit; cost.

## Considered options

| Option | The person's setting decides | Like TextEdit | Opening cost |
| --- | --- | --- | --- |
| **`.automatic` (chosen)** | ✓ | ✓ | no tab merge unless the person prefers tabs |
| `.preferred`, as before | ✗ always tabs | ✗ | a tab merge and a second layout on every open |
| `.disallowed` | ✗ never tabs | ✗ | none |

## Decision

**Decision.** Document windows use `tabbingMode = .automatic`, under one tabbing identifier. A new
document opens as a tab only when System Settings › Desktop & Dock › "Prefer tabs when opening
documents" says so; by default, as in TextEdit, it opens a window. Window › Merge All Windows and
the tab bar work as before (REQ-020, REQ-131).

## Consequences

**Where it is worse.** Someone who liked every document arriving as a tab, without having set
Prefer tabs, now gets windows; Window › Merge All Windows, or the setting, brings tabs back.

The rest of opening a window was attributed too. Of 464 samples in `makeWindowControllers`, 412
were the window's first layout, which `setFrameUsingName` happens to trigger: SwiftUI building the
view graph, AppKit, the allocator, with no hotspot. The app's own code was 54 samples for the
toolbar, 12 for both editors. Nothing short of leaving SwiftUI for the window's content would
shorten that, and the product is SwiftUI-first (CLAUDE.md §1), so it stays.

## Confirmation

`DocumentLifecycleContractTests` and `MacOSCitizenshipTests` assert `tabbingMode = .automatic` under one tabbing identifier (REQ-020, REQ-131).

## Retirement proof

A product decision that documents should always tab, overriding the person's setting.

## Reversal plan

Set `.preferred` again; one line.
