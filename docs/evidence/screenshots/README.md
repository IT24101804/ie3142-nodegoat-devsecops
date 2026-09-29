# Screenshots

Evidence captures referenced by [`../README.md`](../README.md).

## Naming convention

```
<id>-<description>--<run>-<sha>.png
```

- `<id>` — the screenshot ID from the evidence index (`s01`, `s02`, …), zero-padded
  so files sort in index order.
- `<description>` — short kebab-case description.
- `<run>-<sha>` — the CI run and short commit the capture came from, e.g.
  `ci15-b953365`. **Omit this segment entirely** for captures that are not from a
  CI run (repository settings pages, local terminal output, browser screenshots).

The run and commit are in the filename as well as the index deliberately: the
captures are **not all from the same run**, and a filename that carries its own
provenance cannot be mis-attributed if the index and the files ever drift.

## Examples

```
s01-red-job-graph--ci15-b953365.png
s13-dockerhub-login-succeeded--ci20-530da90.png
s12-repository-secrets.png              <- no run: a settings page
s14-vault-init-logs.png                 <- no run: local terminal
```

## Format

PNG preferred. `.gitattributes` treats `*.png`, `*.jpg` and `*.jpeg` as binary, so
they are committed byte-exact with no line-ending translation.
