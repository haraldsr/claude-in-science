"""Fig. 3 of Karlsson et al., Electrochim. Acta 549, 148053 (2026), as a static PNG and an
interactive HTML page. Example result for exercise 3 of the Claude in Science workshop.

    uv run --with pandas --with matplotlib --with plotly python make_fig3.py fig3_ml_binding_energies.csv

Writes fig3_static.png and fig3_interactive.html next to this script.
"""
import json
import re
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
import plotly.graph_objects as go
from matplotlib.patches import Circle

XLIM, YLIM = (-0.5, 1.0), (-2.0, 0.5)
OUT = Path(__file__).resolve().parent
# Rh, Pd and Ir sit almost on top of each other; move their labels apart.
LABEL_OFFSET = {"Rh": (-6, -15), "Pd": (-14, 7), "Ir": (8, -5)}       # matplotlib, in points
LABEL_POSITION = {"Rh": "bottom center", "Pd": "top left", "Ir": "middle right"}  # plotly


def read(csv):
    """Data plus the Cu circle (centre, radius) from the # header."""
    header = "".join(line for line in open(csv) if line.startswith("#"))
    m = re.search(r"centre = Cu reference \(([-\d.]+), ([-\d.]+)\), radius = ([\d.]+)", header)
    cx, cy, r = map(float, m.groups())
    df = pd.read_csv(csv, comment="#")
    df["within_Cu_circle"] = df["within_Cu_circle"].astype("boolean").fillna(False)
    return df, (cx, cy, r)


def static(df, circle):
    cx, cy, r = circle
    mat = df[df.point_type == "material"]
    ref = df[df.point_type == "metal_reference"]
    fig, ax = plt.subplots(figsize=(7, 7))
    ax.scatter(mat.dE_H_eV, mat.dE_CO_eV, s=8, c="grey", alpha=0.5, linewidths=0, zorder=2)
    ax.scatter(ref.dE_H_eV, ref.dE_CO_eV, s=60, c=ref.label_color, edgecolors="black", linewidths=0.6, zorder=3)
    for _, row in ref.iterrows():
        ax.annotate(row.formula, (row.dE_H_eV, row.dE_CO_eV), xytext=LABEL_OFFSET.get(row.formula, (6, 4)),
                    textcoords="offset points",
                    fontweight="bold", color="black", zorder=4)
    ax.add_patch(Circle((cx, cy), r, fill=False, ls="--", lw=1.4, ec="black", zorder=3))
    ax.set(xlim=XLIM, ylim=YLIM, xlabel=r"$\Delta E_{\mathrm{H*}}$ [eV]", ylabel=r"$\Delta E_{\mathrm{CO*}}$ [eV]")
    ax.grid(color="0.9", zorder=0)
    fig.tight_layout()
    fig.savefig(OUT / "fig3_static.png", dpi=150)


def hover_data(d):
    return list(zip(d.formula, d.slab_formula, d.mp_id.fillna("—"), d.distance_to_Cu_eV))


HOVER = ("<b>%{customdata[0]}</b><br>slab: %{customdata[1]}<br>%{customdata[2]}<br>"
         "ΔE<sub>H</sub> = %{x:.3f} eV<br>ΔE<sub>CO</sub> = %{y:.3f} eV<br>"
         "distance to Cu = %{customdata[3]:.3f} eV<extra></extra>")


def interactive(df, circle):
    cx, cy, r = circle
    mat = df[df.point_type == "material"]
    ref = df[df.point_type == "metal_reference"]
    fig = go.Figure()
    # Traces 0 and 1: materials inside and outside the Cu circle, both grey until the toggle is on.
    for name, part in [("inside Cu circle", mat[mat.within_Cu_circle]), ("outside", mat[~mat.within_Cu_circle])]:
        fig.add_trace(go.Scattergl(
            x=part.dE_H_eV, y=part.dE_CO_eV, mode="markers", name=name, showlegend=False,
            marker=dict(size=6, color="grey", opacity=0.5), customdata=hover_data(part), hovertemplate=HOVER))
    # Trace 2: metal references, coloured and labelled.
    fig.add_trace(go.Scatter(
        x=ref.dE_H_eV, y=ref.dE_CO_eV, mode="markers+text", showlegend=False,
        text=[f"<b>{f}</b>" for f in ref.formula], textfont=dict(color="black", size=13),
        textposition=[LABEL_POSITION.get(f, "top right") for f in ref.formula],
        marker=dict(size=11, color=list(ref.label_color), line=dict(color="black", width=0.8)),
        customdata=hover_data(ref), hovertemplate=HOVER))
    # Trace 3: search matches, filled in by the page's script.
    fig.add_trace(go.Scatter(
        x=[], y=[], mode="markers", showlegend=False, hoverinfo="skip",
        marker=dict(size=16, color="rgba(0,0,0,0)", line=dict(color="#e11d48", width=2.5))))
    fig.add_shape(type="circle", xref="x", yref="y", x0=cx - r, x1=cx + r, y0=cy - r, y1=cy + r,
                  line=dict(color="black", dash="dash", width=1.5))
    axis = dict(showgrid=True, gridcolor="#e8e8e8", zeroline=False, linecolor="black", mirror=True, ticks="outside")
    fig.update_layout(
        template="plotly_white", margin=dict(l=70, r=20, t=20, b=60), hovermode="closest",
        xaxis=dict(axis, range=list(XLIM), title="ΔE<sub>H*</sub> [eV]"),
        yaxis=dict(axis, range=list(YLIM), title="ΔE<sub>CO*</sub> [eV]"))

    points = df.assign(mp_id=df.mp_id.fillna(""))[["formula", "mp_id", "dE_H_eV", "dE_CO_eV"]]
    plot = fig.to_html(full_html=False, include_plotlyjs=True, div_id="plot", config={"responsive": True})
    page = TEMPLATE.replace("{{PLOT}}", plot).replace("{{POINTS}}", json.dumps(points.values.tolist()))
    (OUT / "fig3_interactive.html").write_text(page)


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fig. 3 · ML binding energies</title>
<style>
  html, body { margin: 0; height: 100%; font: 14px/1.4 system-ui, sans-serif; color: #111; background: #fff; }
  body { display: flex; flex-direction: column; }
  .bar { display: flex; flex-wrap: wrap; gap: 8px 18px; align-items: center; padding: 10px 14px; border-bottom: 1px solid #e5e5e5; }
  .bar input[type=search] { font: inherit; padding: 5px 9px; border: 1px solid #bbb; border-radius: 6px; width: 15em; }
  .bar label { display: inline-flex; gap: 6px; align-items: center; cursor: pointer; }
  #status { color: #666; }
  #plot { flex: 1; min-height: 420px; }
</style>
</head>
<body>
<div class="bar">
  <label><input type="checkbox" id="inside"> Highlight only materials inside the Cu circle</label>
  <label>Find <input type="search" id="q" placeholder="formula or mp-id, e.g. mp-9929"></label>
  <span id="status"></span>
</div>
{{PLOT}}
<script>
(function () {
  var points = {{POINTS}};  // [formula, mp_id, dE_H, dE_CO]
  var plot = document.getElementById("plot");
  var status = document.getElementById("status");
  document.getElementById("inside").addEventListener("change", function (e) {
    var on = e.target.checked;
    Plotly.restyle(plot, { "marker.color": on ? "#0f766e" : "grey", "marker.opacity": on ? 0.9 : 0.5 }, [0]);
    Plotly.restyle(plot, { "marker.opacity": on ? 0.12 : 0.5 }, [1]);
  });
  document.getElementById("q").addEventListener("input", function (e) {
    var q = e.target.value.trim().toLowerCase();
    var hits = q.length < 2 ? [] : points.filter(function (p) {
      return p[0].toLowerCase() === q || p[1].toLowerCase() === q ||
             (q.length > 2 && (p[0].toLowerCase().indexOf(q) >= 0 || p[1].toLowerCase().indexOf(q) >= 0));
    });
    Plotly.restyle(plot, { x: [hits.map(function (p) { return p[2]; })], y: [hits.map(function (p) { return p[3]; })] }, [3]);
    status.textContent = q.length < 2 ? "" : hits.length === 1 ? "1 match" : hits.length + " matches";
  });
})();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    df, circle = read(sys.argv[1])
    static(df, circle)
    interactive(df, circle)
