# Claude in Science workshop page

Static companion site for the CatTheory & CAMD workshop. No build step: everything is in `public/`.

- `public/index.html` is the whole page (HTML, CSS and JS in one file).
- `public/img/` holds the five figures used in the exercises.

The Claude Code harness the page tells people to install lives in `../Agentic_coding/`. If its
bundle layout or install steps change, update the page's Setup section to match.

## Hosting

GitHub Pages, from `.github/workflows/pages.yml` at the repo root. Every push to `main` that
touches this folder publishes `public/` to https://haraldsr.github.io/claude-in-science/.

One-time setup: Settings > Pages > Build and deployment > Source: GitHub Actions. The workflow
skips itself while the repo is private; after making it public, run it once from the Actions tab
(Pages > Run workflow).

## Editing

Open `public/index.html` in any editor and change the text directly. Fonts load from Google Fonts;
everything else is local. To preview, open the file in a browser.
