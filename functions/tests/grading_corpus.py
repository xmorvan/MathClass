"""Graded student work covering primary school to upper secondary.

Each case is a real-looking copy: the exercise statement, the teacher's
expected answer, the student's steps (LaTeX, as the recognition produces
them) and whether the copy is right. Wrong copies carry the index of the
first wrong step when it is unambiguous.

Used by test_grading_corpus.py (SymPy alone, no AI) and by
grading_benchmark.py (full pipeline with the real Claude).
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class Case:
    id: str
    level: str
    statement: str
    expected: str
    steps: tuple
    correct: bool
    first_error: int | None = None


def _c(id, level, statement, expected, steps, correct, first_error=None):
    return Case(id, level, statement, expected, tuple(steps), correct, first_error)


CASES = [
    # ── Primaire ─────────────────────────────────────────────────────────
    _c("priorites-ok", "primaire", r"Calculer $7 + 8 \times 2$", "23",
       [r"8 \times 2 = 16", r"7 + 16 = 23"], True),
    _c("priorites-faux", "primaire", r"Calculer $7 + 8 \times 2$", "23",
       [r"7 + 8 = 15", r"15 \times 2 = 30"], False, 0),
    _c("soustraction-ok", "primaire", r"Calculer $125 - 48$", "77",
       [r"125 - 48 = 77"], True),
    _c("soustraction-faux", "primaire", r"Calculer $125 - 48$", "77",
       [r"125 - 48 = 87"], False, 0),
    _c("division-deux-points", "primaire", r"Calculer $36 : 4$", "9",
       [r"36 : 4 = 9"], True),
    _c("division-div", "primaire", r"Calculer $36 : 4$", "9",
       [r"36 \div 4 = 9"], True),
    _c("oeufs-ok", "primaire",
       "Une boîte contient 6 œufs. Combien d'œufs y a-t-il dans 7 boîtes ?",
       r"42 \text{ œufs}", [r"6 \times 7 = 42"], True),
    _c("oeufs-faux", "primaire",
       "Une boîte contient 6 œufs. Combien d'œufs y a-t-il dans 7 boîtes ?",
       r"42 \text{ œufs}", [r"6 + 7 = 13"], False, 0),
    _c("billes-ok", "primaire",
       "Paul a 3 paquets de 12 billes et en reçoit encore 5. Combien de billes a-t-il ?",
       "41", [r"3 \times 12 = 36", r"36 + 5 = 41"], True),
    _c("billes-faux", "primaire",
       "Paul a 3 paquets de 12 billes et en reçoit encore 5. Combien de billes a-t-il ?",
       "41", [r"3 \times 12 = 37", r"37 + 5 = 42"], False, 0),
    _c("billes-phrase-ok", "primaire",
       "Paul a 3 paquets de 12 billes et en reçoit encore 5. Combien de billes a-t-il ?",
       "41", [r"3 \times 12 = 36", r"36 + 5 = 41", r"\text{Paul a 41 billes}"], True),
    _c("billes-phrase-fausse", "primaire",
       "Paul a 3 paquets de 12 billes et en reçoit encore 5. Combien de billes a-t-il ?",
       "41", [r"3 \times 12 = 36", r"36 + 5 = 41", r"\text{Paul a 36 billes}"], False, 2),

    # ── Fractions, décimaux, pourcentages ───────────────────────────────
    _c("fractions-ok", "7e-8e", r"Calculer $\frac{1}{2} + \frac{1}{3}$", r"\frac{5}{6}",
       [r"\frac{3}{6} + \frac{2}{6} = \frac{5}{6}"], True),
    _c("fractions-faux", "7e-8e", r"Calculer $\frac{1}{2} + \frac{1}{3}$", r"\frac{5}{6}",
       [r"\frac{1+1}{2+3} = \frac{2}{5}"], False, 0),
    _c("simplifier-ok", "7e-8e", r"Simplifier $\frac{18}{24}$", r"\frac{3}{4}",
       [r"\frac{18}{24} = \frac{9}{12} = \frac{3}{4}"], True),
    _c("simplifier-incomplet", "7e-8e", r"Simplifier $\frac{18}{24}$", r"\frac{3}{4}",
       [r"\frac{18}{24} = \frac{9}{12}"], False, 0),
    _c("decimal-virgule", "7e-8e", r"Calculer $2{,}5 \times 4$", "10",
       [r"2,5 \times 4 = 10"], True),
    _c("pourcentage-ok", "7e-8e", "Calculer 20 % de 150.", "30",
       [r"\frac{20}{100} \times 150 = 30"], True),
    _c("pourcentage-decimal", "7e-8e", "Calculer 20 % de 150.", "30",
       [r"0,2 \times 150 = 30"], True),
    _c("pourcentage-faux", "7e-8e", "Calculer 20 % de 150.", "30",
       [r"150 - 20 = 130"], False, 0),
    _c("relatifs-ok", "7e-8e", r"Calculer $(-4) \times (-5) - 3$", "17",
       [r"20 - 3 = 17"], True),
    _c("relatifs-faux", "7e-8e", r"Calculer $(-4) \times (-5) - 3$", "17",
       [r"-20 - 3 = -23"], False, 0),
    _c("carre-negatif-ok", "7e-8e", r"Calculer $-3^2$", "-9",
       [r"-3^2 = -9"], True),
    _c("carre-negatif-faux", "7e-8e", r"Calculer $-3^2$", "-9",
       [r"-3^2 = 9"], False, 0),

    # ── Puissances, racines, notation scientifique ──────────────────────
    _c("puissances-ok", "9e-10e", r"Calculer $2^3 \times 2^4$", "128",
       [r"2^{3+4} = 2^7 = 128"], True),
    _c("puissances-forme", "9e-10e", r"Calculer $2^3 \times 2^4$", "128",
       [r"2^3 \times 2^4 = 8 \times 16 = 128"], True),
    _c("puissances-faux", "9e-10e", r"Calculer $2^3 \times 2^4$", "128",
       [r"2^{3 \times 4} = 2^{12}"], False, 0),
    _c("racine-ok", "9e-10e", r"Simplifier $\sqrt{50}$", r"5\sqrt{2}",
       [r"\sqrt{25 \times 2} = 5\sqrt{2}"], True),
    _c("racine-faux", "9e-10e", r"Simplifier $\sqrt{50}$", r"5\sqrt{2}",
       [r"\sqrt{50} = 25\sqrt{2}"], False, 0),
    _c("scientifique-ok", "9e-10e", r"Écrire $0{,}00045$ en notation scientifique",
       r"4,5 \times 10^{-4}", [r"4,5 \times 10^{-4}"], True),
    _c("scientifique-forme", "9e-10e", r"Écrire $0{,}00045$ en notation scientifique",
       r"4,5 \times 10^{-4}", [r"45 \times 10^{-5}"], False, 0),
    _c("scientifique-faux", "9e-10e", r"Écrire $0{,}00045$ en notation scientifique",
       r"4,5 \times 10^{-4}", [r"4,5 \times 10^{4}"], False, 0),

    # ── Calcul littéral ─────────────────────────────────────────────────
    _c("developper-ok", "9e-10e", r"Développer $3(x + 4)$", "3x + 12",
       ["3x + 12"], True),
    _c("developper-detail", "9e-10e", r"Développer $3(x + 4)$", "3x + 12",
       [r"3 \times x + 3 \times 4 = 3x + 12"], True),
    _c("developper-faux", "9e-10e", r"Développer $3(x + 4)$", "3x + 12",
       ["3x + 4"], False, 0),
    _c("identite-ok", "9e-10e", r"Développer $(x + 3)^2$", "x^2 + 6x + 9",
       [r"x^2 + 2 \times 3x + 9 = x^2 + 6x + 9"], True),
    _c("identite-faux", "9e-10e", r"Développer $(x + 3)^2$", "x^2 + 6x + 9",
       ["x^2 + 9"], False, 0),
    _c("factoriser-ok", "9e-10e", r"Factoriser $x^2 - 9$", "(x - 3)(x + 3)",
       ["(x - 3)(x + 3)"], True),
    _c("factoriser-non-fait", "9e-10e", r"Factoriser $x^2 - 9$", "(x - 3)(x + 3)",
       [r"x^2 - 9 = x^2 - 3^2"], False, 0),
    _c("factoriser-faux", "9e-10e", r"Factoriser $x^2 - 9$", "(x - 3)(x + 3)",
       ["(x - 3)^2"], False, 0),
    _c("reduire-ok", "9e-10e", r"Réduire $5x - 2x + 3 - 7$", "3x - 4",
       ["3x - 4"], True),
    _c("reduire-faux", "9e-10e", r"Réduire $5x - 2x + 3 - 7$", "3x - 4",
       ["3x + 4"], False, 0),

    # ── Équations et inéquations ────────────────────────────────────────
    _c("eq1-ok", "9e-10e", r"Résoudre $2(x + 3) = 14$", "x = 4",
       ["2x + 6 = 14", "2x = 8", "x = 4"], True),
    _c("eq1-fraction-intermediaire", "9e-10e", r"Résoudre $2(x + 3) = 14$", "x = 4",
       ["2x + 6 = 14", r"x = \frac{8}{2} = 4"], True),
    _c("eq1-faux", "9e-10e", r"Résoudre $2(x + 3) = 14$", "x = 4",
       ["2x + 3 = 14", "2x = 11", "x = 5,5"], False, 0),
    _c("eq1-signe-faux", "9e-10e", r"Résoudre $5x - 7 = 2x + 8$", "x = 5",
       ["7x = 15", r"x = \frac{15}{7}"], False, 0),
    _c("eq1-deux-membres-ok", "9e-10e", r"Résoudre $5x - 7 = 2x + 8$", "x = 5",
       ["3x = 15", "x = 5"], True),
    _c("eq1-parentheses-ok", "9e-10e", r"Résoudre $3 - (x - 2) = 1$", "x = 4",
       ["3 - x + 2 = 1", "5 - x = 1", "x = 4"], True),
    _c("eq1-parentheses-faux", "9e-10e", r"Résoudre $3 - (x - 2) = 1$", "x = 4",
       ["3 - x - 2 = 1", "1 - x = 1", "x = 0"], False, 0),
    _c("eq-fraction-ok", "9e-10e", r"Résoudre $\frac{x}{3} + 1 = 5$", "x = 12",
       [r"\frac{x}{3} = 4", r"x = 4 \times 3 = 12"], True),
    _c("eq-reponse-fraction", "9e-10e", r"Résoudre $3x = 2$", r"x = \frac{2}{3}",
       [r"x = \frac{2}{3}"], True),
    _c("eq-reponse-fraction-faux", "9e-10e", r"Résoudre $3x = 2$", r"x = \frac{2}{3}",
       ["x = 1,5"], False, 0),
    _c("eq2-ok", "11e", r"Résoudre $x^2 - 5x + 6 = 0$", r"x = 2 \text{ ou } x = 3",
       ["(x - 2)(x - 3) = 0", r"x = 2 \text{ ou } x = 3"], True),
    _c("eq2-ensemble", "11e", r"Résoudre $x^2 - 5x + 6 = 0$", r"x = 2 \text{ ou } x = 3",
       ["(x - 2)(x - 3) = 0", r"S = \{2 ; 3\}"], True),
    _c("eq2-incomplet", "11e", r"Résoudre $x^2 = 16$", r"x = 4 \text{ ou } x = -4",
       ["x = 4"], False, 0),
    _c("inequation-ok", "11e", r"Résoudre $2x - 3 < 7$", "x < 5",
       ["2x < 10", "x < 5"], True),
    _c("inequation-sens-faux", "11e", r"Résoudre $-2x < 6$", "x > -3",
       ["x < -3"], False, 0),
    _c("systeme-ok", "11e", r"Résoudre le système $x + y = 10$ et $x - y = 2$",
       r"x = 6 \text{ et } y = 4", ["2x = 12", "x = 6", "y = 4"], True),
    _c("systeme-faux", "11e", r"Résoudre le système $x + y = 10$ et $x - y = 2$",
       r"x = 6 \text{ et } y = 4", ["x = 5", "y = 5"], False, 0),

    # ── Géométrie, grandeurs, proportionnalité ──────────────────────────
    _c("pythagore-ok", "9e-10e",
       "Un triangle rectangle a des côtés de l'angle droit de 6 cm et 8 cm. Calculer la longueur de l'hypoténuse.",
       r"10 \text{ cm}", ["c^2 = 6^2 + 8^2 = 100", "c = 10"], True),
    _c("pythagore-faux", "9e-10e",
       "Un triangle rectangle a des côtés de l'angle droit de 6 cm et 8 cm. Calculer la longueur de l'hypoténuse.",
       r"10 \text{ cm}", ["c = 6 + 8 = 14"], False, 0),
    _c("disque-ok", "9e-10e", "Calculer l'aire exacte d'un disque de rayon 3 cm.",
       r"9\pi \text{ cm}^2", [r"\pi \times 3^2 = 9\pi"], True),
    _c("disque-perimetre", "9e-10e", "Calculer l'aire exacte d'un disque de rayon 3 cm.",
       r"9\pi \text{ cm}^2", [r"2 \pi \times 3 = 6\pi"], False, 0),
    _c("prix-ok", "7e-8e", "3 kg de pommes coûtent 7,50 CHF. Combien coûtent 5 kg ?",
       r"12,50 \text{ CHF}", ["7,50 : 3 = 2,50", r"2,50 \times 5 = 12,50"], True),
    _c("prix-faux", "7e-8e", "3 kg de pommes coûtent 7,50 CHF. Combien coûtent 5 kg ?",
       r"12,50 \text{ CHF}", ["7,50 + 2 = 9,50"], False, 0),
    _c("conversion-ok", "primaire", "Convertir 2,5 km en mètres.", r"2500 \text{ m}",
       [r"2,5 \times 1000 = 2500"], True),
    _c("conversion-faux", "primaire", "Convertir 2,5 km en mètres.", r"2500 \text{ m}",
       [r"2,5 \times 100 = 250"], False, 0),

    # ── Fonctions, analyse (secondaire II) ──────────────────────────────
    _c("image-ok", "11e", r"Soit $f(x) = 2x^2 - x$. Calculer $f(3)$.", "15",
       [r"f(3) = 2 \times 9 - 3 = 15"], True),
    _c("image-faux", "11e", r"Soit $f(x) = 2x^2 - x$. Calculer $f(3)$.", "15",
       [r"f(3) = 2 \times 6 - 3 = 9"], False, 0),
    _c("derivee-ok", "sec-II", r"Dériver $f(x) = x^3 - 4x$", "f'(x) = 3x^2 - 4",
       ["f'(x) = 3x^2 - 4"], True),
    _c("derivee-faux", "sec-II", r"Dériver $f(x) = x^3 - 4x$", "f'(x) = 3x^2 - 4",
       ["f'(x) = 3x^2 - 4x"], False, 0),
    _c("derivee-produit-ok", "sec-II", r"Dériver $f(x) = x e^x$", "f'(x) = (x + 1)e^x",
       ["f'(x) = e^x + x e^x = (x + 1)e^x"], True),
    _c("derivee-produit-faux", "sec-II", r"Dériver $f(x) = x e^x$", "f'(x) = (x + 1)e^x",
       ["f'(x) = e^x"], False, 0),
    _c("integrale-ok", "sec-II", r"Calculer $\int_0^2 x^2 \, dx$", r"\frac{8}{3}",
       [r"\left[\frac{x^3}{3}\right]_0^2 = \frac{8}{3}"], True),
    _c("integrale-faux", "sec-II", r"Calculer $\int_0^2 x^2 \, dx$", r"\frac{8}{3}",
       [r"\left[2x\right]_0^2 = 4"], False, 0),
    _c("limite-ok", "sec-II", r"Calculer $\lim_{x \to 2} \frac{x^2 - 4}{x - 2}$", "4",
       [r"\frac{(x-2)(x+2)}{x-2} = x + 2", r"\lim_{x \to 2} (x + 2) = 4"], True),
    _c("limite-faux", "sec-II", r"Calculer $\lim_{x \to 2} \frac{x^2 - 4}{x - 2}$", "4",
       [r"\frac{0}{0} = 0"], False, 0),
    _c("exp-ok", "sec-II", r"Résoudre $e^x = 5$", r"x = \ln 5",
       [r"x = \ln(5)"], True),
    _c("exp-faux", "sec-II", r"Résoudre $e^x = 5$", r"x = \ln 5",
       [r"x = \frac{5}{e}"], False, 0),
    _c("trigo-ok", "sec-II", r"Simplifier $\sin^2 x + \cos^2 x$", "1", ["1"], True),
    _c("trigo-faux", "sec-II", r"Simplifier $\sin^2 x + \cos^2 x$", "1", ["0"], False, 0),

    # ── Probabilités, statistiques ──────────────────────────────────────
    _c("proba-ok", "9e-10e", "On lance un dé équilibré. Quelle est la probabilité d'obtenir un nombre pair ?",
       r"\frac{1}{2}", [r"\frac{3}{6} = \frac{1}{2}"], True),
    _c("proba-decimal", "9e-10e", "On lance un dé équilibré. Quelle est la probabilité d'obtenir un nombre pair ?",
       r"\frac{1}{2}", ["0,5"], True),
    _c("proba-faux", "9e-10e", "On lance un dé équilibré. Quelle est la probabilité d'obtenir un nombre pair ?",
       r"\frac{1}{2}", [r"\frac{1}{6}"], False, 0),
    _c("moyenne-ok", "7e-8e", "Calculer la moyenne des notes 12, 15, 9 et 14.", "12,5",
       [r"\frac{12 + 15 + 9 + 14}{4} = \frac{50}{4} = 12,5"], True),
    _c("moyenne-faux", "7e-8e", "Calculer la moyenne des notes 12, 15, 9 et 14.", "12,5",
       [r"\frac{50}{5} = 10"], False, 0),
]
