# Modular startup scripts

## Goal

Split the workstation startup sequence into independently maintainable steps while preserving its order and fail-loud behavior.

## Milestones

1. Replace `.startup` command bodies with a deterministic step runner.
2. Move SSH, Colima, AI-service, and Homebrew operations into ordered scripts under `.startup.d/`.
3. Add an isolated shell test for ordering and failure propagation.
4. Update the project map and archive this plan after review.


## Review Log

- **2026-08-25 — Reviewer: APPROVED.** The runner is deterministic and fail-loud, the steps remain behaviorally equivalent, and tests cover ordering and failure propagation.

## Expectation vs. Reality

The split mapped directly to the four existing responsibility groups. A small
runner and an overridable `STARTUP_DIR` made isolated testing possible without
executing workstation side effects.
