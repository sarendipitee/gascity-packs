# Release Workflow

This diagram shows how tested pack work moves from `default@` to GitHub.

## Release steps

```mermaid
flowchart TD
  start["Release triggered after live testing on default@"]
  fetch["jj git fetch"]
  check{"main@origin ahead of main?"}
  rebase["jj rebase -s main -d main@origin"]
  merge["jj new main@origin default@ -m 'Land packs'"]
  move_main["jj bookmark move main --to @"]
  verify["gc lint <pack>"]
  push["jj git push"]
  confirm["main@origin == main"]

  start --> fetch
  fetch --> check
  check -->|yes| rebase
  check -->|no| merge
  rebase --> merge
  merge --> move_main --> verify --> push --> confirm
```

## Notes

- Release only after the pack has been tested on `default@` in a running Gas
  City.
- Always fetch first. `main@origin` is the live target.
- If origin has moved, rebase local `main` onto `main@origin` before landing.
- The release commit merges the tested `default@` state onto `main@origin`.
- After moving `main`, verify the landed packs still lint cleanly.
- Push only after verification.
- Do not push `gc/*` workspace bookmarks to origin; they are local-only.
