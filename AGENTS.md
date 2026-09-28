# Timescale development workflow

- Use jj for version control; this repository is jj/git colocated.
- Keep development on a single linear trunk of changes on top of `main` by default.
  Do not create separate feature branches or isolated publication checkouts unless
  the task requires them.
- Rebase the active working change or stack onto `main` as needed, resolving
  overlaps with the latest implementation while preserving newer fixes on `main`.
- Mutating jj commands are allowed as needed to complete the task. Preserve
  unrelated work and coordinate with agents sharing this checkout.
- Push through the user's jj aliases when publication is requested.
