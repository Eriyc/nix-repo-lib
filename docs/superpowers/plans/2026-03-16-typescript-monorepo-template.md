# TypeScript Monorepo Template Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the minimal starter template with a Bun-only Moonrepo + TypeScript + Varlock monorepo template exposed through the existing flake template.

**Architecture:** Expand `template/` into a complete repository skeleton while keeping `repo-lib.lib.mkRepo` as the integration point. Adapt the strict TypeScript config layout and Varlock command pattern from `../moon`, and update release tests so they evaluate the full template contents.

**Tech Stack:** Nix flakes, repo-lib, Bun, Moonrepo, Varlock, TypeScript

---

## Chunk 1: Documentation Baseline

### Task 1: Update public template docs

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write the failing expectation mentally against current docs**

Current docs describe only a minimal starter template and do not mention Bun, Moonrepo, or Varlock.

- [ ] **Step 2: Update the README to describe the new template**

Document the generated workspace shape and first-run commands.

- [ ] **Step 3: Verify the README content is consistent with the template files**

Check all commands and filenames against the final template layout.

## Chunk 2: Template Skeleton

### Task 2: Replace the minimal template with a real monorepo skeleton

**Files:**
- Modify: `template/flake.nix`
- Create: `template/package.json`
- Create: `template/bunfig.toml`
- Create: `template/moon.yml`
- Create: `template/tsconfig.json`
- Create: `template/tsconfig.options.json`
- Create: `template/tsconfig/browser.json`
- Create: `template/tsconfig/bun.json`
- Create: `template/tsconfig/package.json`
- Create: `template/tsconfig/runtime.json`
- Create: `template/.env.schema`
- Modify: `template/.gitignore`
- Create: `template/README.md`
- Create: `template/apps/.gitkeep`
- Create: `template/packages/.gitkeep`

- [ ] **Step 1: Add or update template files**

Use `../moon` as the source for Moonrepo, Varlock, and TypeScript patterns, removing product-specific details.

- [ ] **Step 2: Verify the template tree is coherent**

Check that all referenced files exist and that scripts reference only template-safe commands.

## Chunk 3: Test Coverage

### Task 3: Update release tests for the full template

**Files:**
- Modify: `tests/release.sh`

- [ ] **Step 1: Add a failing test expectation**

The current template fixture copies only `template/flake.nix`, which is insufficient for the new template layout.

- [ ] **Step 2: Update fixture creation to copy the full template**

Rewrite template URL references in copied files as needed for local test evaluation.

- [ ] **Step 3: Verify the existing template evaluation case now uses the real skeleton**

Confirm `nix flake show` runs against the expanded template fixture.

## Chunk 4: Verification

### Task 4: Run template verification

**Files:**
- Verify: `README.md`
- Verify: `template/**/*`
- Verify: `tests/release.sh`

- [ ] **Step 1: Run the release test suite**

Run: `nix develop -c bash tests/release.sh`

- [ ] **Step 2: Inspect the template file tree**

Run: `find template -maxdepth 3 -type f | sort`

- [ ] **Step 3: Verify the README examples still match the tagged template release pattern**

Check that versioned `repo-lib` URLs remain in the documented commands and release replacements.
