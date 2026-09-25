"""Build website/confidentialite.html from docs/legal/politique-confidentialite.md.

Run from the repository root after editing the policy:
    python3 website/tools/build_privacy.py
Needs the `markdown` package (pip install markdown).
"""

from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs" / "legal" / "politique-confidentialite.md"
TARGET = ROOT / "website" / "confidentialite.html"

body = markdown.markdown(SOURCE.read_text(encoding="utf-8"), extensions=["tables"])
body = body.replace("<table>", '<div class="table-scroll"><table>').replace("</table>", "</table></div>")

page = f"""<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>Confidentialité MathClass</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Source+Sans+3:wght@400;600;700&family=Zilla+Slab:wght@600;700&display=swap">
  <link rel="stylesheet" href="style.css">
  <link rel="icon" href="icon.png">
</head>
<body>
  <div class="wrap">
    <header class="site-header">
      <a class="brand" href="index.html"><span class="brand-mark" aria-hidden="true">x²</span>MathClass</a>
      <nav class="site-nav" aria-label="Sections">
        <a href="index.html#essai">Essayer</a>
      </nav>
    </header>
    <main class="doc">
      <article class="doc-body">
{body}
      </article>
    </main>
    <footer class="site-footer">
      <span>MathClass, Genève</span>
      <nav aria-label="Informations"><a href="index.html">Accueil</a></nav>
    </footer>
  </div>
</body>
</html>
"""
TARGET.write_text(page, encoding="utf-8")
print(f"wrote {TARGET.relative_to(ROOT)}")
