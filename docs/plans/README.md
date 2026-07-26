# Plans

This directory contains only approved, unimplemented production plans. Several plans may coexist
while waiting to be built. A plan is deleted in the same change that completes its implementation;
Git retains the historical plan.

Plans implement the current architecture in `../ENGINEERING.md`. They do not redefine it. Every
plan must name:

- requirements and `ARC-###` invariants;
- architecture impact (`none` unless separately researched and approved);
- exact production files/types/routes to add, modify, and delete;
- ordered implementation phases;
- automated non-UI proof;
- instrumentation and performance evidence;
- failure and rollback behavior; and
- a deletion/conformance gate proving no displaced path remains.
