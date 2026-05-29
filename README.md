# discourse-tc-aria-patches

A focused Discourse theme component for explicit accessibility DOM patches.

This component applies hard-coded ARIA and toolbar adjustments to fix screen reader behavior where generic selector/action systems are not precise enough.

## Current patches

- Composer toolbar buttons: copy `title` to `aria-label`.
- Composer toolbar buttons: remove `aria-keyshortcuts` to prevent shortcut letter announcements in some screen reader/browser combinations.

## Setting

- `aria_patches_debug`: logs patch activity to browser console.
