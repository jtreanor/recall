# Recall — Claude Code Instructions

## Before starting significant work
- Read `docs/plan.md` to understand current phase, status, and next task
- Read `docs/research.md` if touching architecture decisions

## Planning
- Plan before coding meaningful features
- Propose an approach in chat; wait for confirmation before implementing
- For small, clearly scoped tasks, proceed directly

## Code principles
- Native macOS only (Swift + AppKit/SwiftUI hybrid)
- Do not add SPM dependencies without a blocking reason and explicit approval
- Prefer incremental changes over large rewrites
- Do not add non-essential features without asking

## The core product
- The keyboard-first overlay is the core UX — preserve it in every decision
- The value is: summon → glance → arrow to item → Enter → paste
- Optimize for great daily-use feel, not feature completeness
- If a change doesn't improve the core loop, defer it

## Plan maintenance
- Update `docs/plan.md` when implementation diverges from plan
- Mark milestones complete as they are finished
- Update "Current Status" and "Next task" sections

## Git workflow
- Never push directly to `master`
- All work on feature branches: `feature/<short-description>`
- Open a PR via `gh pr create` for every meaningful change
- Keep PRs small and reviewable (one milestone or one logical unit)
- Wait for review and merge; do not self-merge
- Commit messages: imperative mood, short subject line

## Distribution
- Target: direct distribution (notarized), not Mac App Store
- No sandbox; Hardened Runtime enabled
- Accessibility permission required at runtime — handle gracefully
