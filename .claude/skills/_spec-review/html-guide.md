# Spec HTML: authoring guide (PM spec and dev spec)

The `.html` is the copy the human reads and annotates. Goal: the user understands the plan in a few minutes and can point at any part of it to say "change this". It must describe the same plan as the `.md`, but it is not a rendering of it.

## Pick the right form per section

| Content | Form |
|---|---|
| Overall flow, components, sequence, state changes | Hand-written inline SVG diagram |
| Scenarios | Numbered step-through, one panel per step (before / after), happy path first |
| Files to change | Table: path, new or modified, what, why. Group by package |
| Phases | One card each: goal, steps, risk, depends on |
| Alternatives, trade-offs | Small comparison table with a recommended row |
| Decisions the user must make | Explicit choice block (radio-like list with a recommendation), not buried prose |
| Research | One short block: searched, found, Use / Reuse / Build |
| PM spec: target behavior | The ASCII/UI mockups rendered as styled monospace panels, one per STATE, labelled |
| PM spec: behavior rules, success criteria, out of scope | Plain lists; success criteria as a checklist |

Lead with the question a section answers. Assume the reader has not read the code. One idea per diagram; several simple diagrams beat one dense one. Put dense detail (file lists, signatures) below the picture, not inside it.

## Anchors (this is what makes feedback useful)

Give every reviewable block a stable `data-spec` id that matches the corresponding section in the `.md`:

```html
<section data-spec="phase-2"> ... </section>      <!-- md: "### Phase 2" -->
<section data-spec="scenario-3"> ... </section>   <!-- md: "## 3 - ..." -->
<section data-spec="architecture-changes"> ... </section>
```

The review panel records the nearest `data-spec` with every note, so `poll` output reads `spec=phase-2`. Use kebab-case, keep ids stable across edits (do not rename a block when revising it), and nest freely (`phase-2`, `phase-2-step-1`). For SVG, give meaningful nodes and edges an `id` and a `<title>`.

## Diagrams

- Inline SVG, `viewBox` plus `width: 100%`, never fixed pixel sizes. Keep everything inside the viewBox.
- Colors through CSS custom properties and `currentColor` so the figure follows light and dark themes.
- Short labels (a few words); put explanation in HTML beside the figure. SVG text does not wrap.
- Draw from real names: actual modules, files, socket ops, states. No abstract "Component A".
- Label uncertain relationships as questions so the user can resolve them.
- Do not hand-build box-and-arrow diagrams from div/flexbox.

## Page rules

- One self-contained file: inline CSS and JS, no CDN, no external fonts. Local images only if copied next to the file and referenced relatively.
- Define colors as CSS variables on `:root`, set an explicit `body` background and text color, and provide a dark variant with `@media (prefers-color-scheme: dark)`. The review panel adds its own padding on the right at widths >= 900px.
- Works at phone width: no horizontal page scroll, readable at 375px.
- Interactivity is fine (the review panel's "Pick elements" toggle, Alt+A, turns off click-to-comment so a demo or simulator on the page can be used; it is also off whenever the panel is hidden) (tabs, collapsible scenarios, step buttons), but the content of collapsed parts must still be reachable. Prefer `<details>` over custom widgets.
- Keep the first screen useful: title, one-paragraph summary, and the main diagram.
- Plan for revision: when feedback changes the spec, edit the affected blocks in place and keep their `data-spec` ids.

## Skeleton

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Spec: FEATURE</title>
<style>
  :root { --bg:#fbfaf7; --fg:#1c1b19; --muted:#6b675f; --line:#dcd8cf; --card:#fff; --accent:#b4540a; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#161513; --fg:#ece8df; --muted:#a29d92; --line:#3a3732; --card:#1f1d1a; --accent:#e08a3c; }
  }
  body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.55 system-ui, sans-serif; }
  main { max-width:880px; margin:0 auto; padding:24px 16px 80px; }
  section { margin:32px 0; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:14px 16px; }
  svg { width:100%; height:auto; color:var(--fg); }
</style>
</head>
<body>
<main>
  <header data-spec="summary"> <h1>FEATURE</h1> <p>Two or three sentences.</p> </header>
  <section data-spec="flow"> <h2>How it works</h2> <!-- inline svg --> </section>
  <section data-spec="scenarios"> <h2>Scenarios</h2> ... </section>
  <section data-spec="architecture-changes"> <h2>Files</h2> <!-- table --> </section>
  <section data-spec="phases"> <h2>Phases</h2> ... </section>
  <section data-spec="decisions"> <h2>Decisions for you</h2> ... </section>
</main>
</body>
</html>
```

## Before showing it

- Open it directly (no review server) and check light and dark, and a narrow width.
- Every `data-spec` id has a matching section in the `.md`, and every phase and file path in the page appears in the `.md`.
