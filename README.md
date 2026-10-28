# Claude in Science workshop page

Static companion site for the CatTheory & CAMD workshop. No build step: everything is in `docs/`.

- `docs/index.html` is the whole page (HTML, CSS and JS in one file).
- `docs/img/` holds the five figures used in the exercises.

The Claude Code harness the page tells people to install lives in the CatTheory GitLab repo
(`cattheory_tutorials/Agentic_coding`). If its bundle layout or install steps change, update the
page's Setup section to match.

## Hosting

GitHub Pages, served straight from `docs/` with no workflow: Settings > Pages > Build and
deployment > Deploy from a branch > `main` / `/docs`. The page then appears at
`https://haraldsr.github.io/claude-in-science/`. Pages on a private repo needs a paid GitHub
plan; on a public repo it is free.

## Editing

Open `docs/index.html` in any editor and change the text directly. Fonts load from Google Fonts;
everything else is local. To preview, open the file in a browser.
