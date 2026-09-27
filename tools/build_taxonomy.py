"""Builds the skill taxonomy JSON (functions/taxonomy.json and the app's
Core/Resources/Taxonomy.json) from functions/taxonomy_source.txt."""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "functions" / "taxonomy_source.txt"
OUTPUTS = [ROOT / "functions" / "taxonomy.json", ROOT / "Core" / "Resources" / "Taxonomy.json"]
ID = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


def parse(text):
    domains, seen = [], set()
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        marker, rest = line.split(" ", 1)
        parts = [p.strip() for p in rest.split("|")]
        if len(parts) != 3 or not ID.match(parts[0]):
            sys.exit(f"line {number}: expected 'id | Libellé | Label', got {raw!r}")
        key, fr, en = parts
        if marker == "#":
            domains.append({"id": key, "fr": fr, "en": en, "competencies": []})
            full = key
        elif marker == "##":
            domain = domains[-1]
            full = f"{domain['id']}.{key}"
            domain["competencies"].append({"id": full, "fr": fr, "en": en, "skills": []})
        elif marker == "-":
            competency = domains[-1]["competencies"][-1]
            full = f"{competency['id']}.{key}"
            competency["skills"].append({"id": full, "fr": fr, "en": en})
        else:
            sys.exit(f"line {number}: unknown marker {marker!r}")
        if full in seen:
            sys.exit(f"line {number}: duplicate id {full}")
        seen.add(full)
    return {"version": 1, "domains": domains}


if __name__ == "__main__":
    taxonomy = parse(SOURCE.read_text(encoding="utf-8"))
    text = json.dumps(taxonomy, ensure_ascii=False, indent=1) + "\n"
    for output in OUTPUTS:
        output.write_text(text, encoding="utf-8")
    skills = sum(len(c["skills"]) for d in taxonomy["domains"] for c in d["competencies"])
    competencies = sum(len(d["competencies"]) for d in taxonomy["domains"])
    print(f"{len(taxonomy['domains'])} domaines, {competencies} compétences, {skills} savoir-faire")
