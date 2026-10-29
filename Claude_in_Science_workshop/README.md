# Claude in Science workshop page

Static companion site for the CatTheory & CAMD workshop. No build step: everything is in `public/`.

- `public/index.html` is the whole page (HTML, CSS and JS in one file).
- `public/img/` holds the figures used in the exercises (`volcano.png` is the copy Claude downloads in exercise 2).
- `public/data/` and `public/examples/` hold exercise material served from the site: the Fig. 3 data for
  exercise 3, the example result for it (`examples/fig3/`, made by `make_fig3.py`; rerun it to rebuild),
  and the example talk for exercise 4.
- `qr/` holds QR codes for the published page, for slides and handouts (not part of the site):
  `qr-code` has a CO-on-a-surface icon in the centre, `qr-code-github` the GitHub mark.
  `qr/make_qr.py` regenerates them; its docstring says how, and how to add another logo.

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

Each `<section class="section">` in `<main>` shows as its own page, picked by the URL hash
(`#setup`, `#niflheim`, …); the masthead is the Home page. To add a page, add a section with an
`id` and a matching link in the `.rail` nav; its order there sets the Previous/Next buttons.
A rail link with `data-group="x"` stands for a group of pages: their links go in the
`.rail-sub[data-sub="x"]` row, which shows under the rail while one of them is open.
Without JavaScript the page falls back to one long scroll.

The exercises page shows one exercise at a time. Its themes are the `.ex-theme` groups in
`.ex-nav`; each link's `data-ex-link` names an `<article class="ex">`, and Previous/Next steps
through the exercises in that order. To add one, add an article and a link in its theme.
