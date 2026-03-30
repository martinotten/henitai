# Architektur: Ruby-Mutation-Testing-Framework
## Konsolidierter Entwurf auf Basis von 39 wissenschaftlichen Papieren (1992–2025) + Stryker-Ökosystem-Analyse

> **Zielplattform:** Ruby 4 (YJIT, Ractor, `RubyVM::AbstractSyntaxTree`)
> **Stand:** März 2026
> **Referenzbasis:** 39 Paper (`/summaries/`), mutant-Gem-Analyse (`mutant_analysis.md`), Stryker-Ökosystem (`stryker_analysis.md`)
> **Ökosystem-Positionierung:** Kompatibel mit Stryker-Dashboard & mutation-testing-elements

---

## 1. Vision & Designprinzipien

Das Framework verfolgt vier übergeordnete Ziele, die sich aus der Industrieerfahrung von Google (Petrović et al. 2018, 2021), dem GitHub-Adoptionssurvey (Sánchez et al. 2022) und der Stryker-Ökosystem-Analyse ableiten:

**Prinzip 1 — Aktionierbarkeit vor Vollständigkeit.** Google benötigte sechs Jahre iterativer Verbesserung, um den Anteil nicht-produktiver Mutanten von 85 % auf 11 % zu senken. Das wichtigste Design-Kriterium ist nicht die Mutation Score-Maximierung, sondern dass jeder gemeldete Mutant für den Entwickler unmittelbar verständlich und relevant ist.

**Prinzip 2 — Kosten sind kein nachträgliches Problem.** Mutation Testing ist ohne Kostensenkung bei realen Projekten nicht praktikabel. Selektive Mutation, inkrementelle Analyse und Test-Priorisierung sind keine optionalen Features — sie sind Teil der Kern-Pipeline.

**Prinzip 3 — Erweiterbarkeit durch Schichten.** Die Architektur folgt einem klaren Layer-Modell, das MVP-Implementierung ermöglicht, ohne spätere Erweiterungen (LLM-Integration, verteilte Ausführung, latente Mutanten) zu verbauen.

**Prinzip 4 — Ökosystem-Kompatibilität statt Isolation.** Das Framework produziert das Stryker-kompatible `mutation-testing-report-schema`-JSON. Damit stehen Dashboard, HTML-Report, Badges und alle zukünftigen Stryker-Tools vom ersten Tag an zur Verfügung. Ruby ist die einzige Sprache ohne Stryker-Implementierung — wir schließen diese Lücke.

---

## 2. Ruby-4-Spezifika

### 2.1 Verfügbare AST-Infrastruktur

Ruby 4 bietet drei Ebenen für die Mutation:

| Ebene | Mechanismus | Eignung |
|---|---|---|
| **Source-Level** | `parser` Gem (RuboCop-kompatibel) | Primär empfohlen |
| **AST-Level** | `RubyVM::AbstractSyntaxTree` (nativ) | Für einfache Traversierung |
| **IR/Bytecode** | YARV-Instruktionen (via `RubyVM::InstructionSequence`) | Nicht empfohlen — Äquivalenz-Analyse zu aufwändig |

**Entscheidung:** AST-basierte Mutation via `parser` Gem. Regex-basierte Ansätze sind explizit ausgeschlossen — der RegularMutator-Fehler (Ivanova & Khritankov 2020) zeigt, dass Regex-Mutation in Solidity 84,5 % Compilation-Fehler produziert. Dasselbe gilt für Ruby.

### 2.2 Ruby-spezifische Sprachmerkmale

Ruby 4 bringt Eigenschaften, die Standard-Operatoren aus der Literatur nicht abdecken:

- **Open Classes / Monkey-Patching:** Methoden können zur Laufzeit überschrieben werden → Operator `MethodRedefinition` (MRD) notwendig
- **Blocks, Procs, Lambdas:** Closure-Semantik unterscheidet sich; `&block`-Übergabe ist ein eigener Mutations-Kandidat
- **Ractor (Ruby 3+):** Nebenläufige Ausführungseinheiten; Race-Condition-Mutationen für parallelen Code
- **YJIT:** JIT-Optimierungen können Code-Verhalten unterschiedlich kompilieren; Framework muss YJIT-konsistente Ausführung sicherstellen
- **Pattern Matching (Ruby 3+):** `case/in`-Ausdrücke benötigen eigene Operatoren (Pattern-Replacement)
- **Endless Methods (`def f = expr`):** Müssen im AST-Traversal gesondert behandelt werden

### 2.3 Parallelisierungsstrategie

Ruby 4 bietet drei Parallelisierungsmodelle:

```
Ractor (shared-nothing concurrency)  →  für Mutanten-Execution isoliert
Process.fork / Parallel-Gem          →  für Test-Execution (breiter Ökosystem-Support)
Fibers                               →  NICHT geeignet (kooperativ, kein echter Parallelismus)
```

**Empfehlung:** Process-basierte Parallelisierung für Test-Execution (vollständige Isolation, kein GVL-Problem). Ractor für die Mutanten-Generierungsphase, wo keine Ruby-Extension-Gems involviert sind.

---

## 3. Architektur-Überblick

```
┌─────────────────────────────────────────────────────────────┐
│                      CLI / API Interface                      │
│          henitai run [options] [SUBJECT_PATTERN...]            │
└────────────────────────┬────────────────────────────────────┘
                         │
         ┌───────────────▼───────────────┐
         │      Orchestrator             │
         │  - Config resolution          │
         │  - Budget enforcement         │
         │  - Phase coordination         │
         └──┬──────────────────────┬────┘
            │                      │
   ┌────────▼────────┐    ┌────────▼────────┐
   │  Source Analyzer │    │  Test Inventory  │
   │  - Git diff      │    │  - RSpec/MTest   │
   │  - AST parsing   │    │  - Coverage map  │
   │  - Arid-Node     │    │  - Flaky detect  │
   │    filtering     │    │                  │
   └────────┬────────┘    └────────┬────────┘
            │                      │
         ┌──▼──────────────────────▼──┐
         │      Mutant Generator       │
         │  - Operator registry        │
         │  - Selective application    │
         │  - Stillborn filtering      │
         │  - Sampling strategy        │
         └──────────────┬─────────────┘
                        │
         ┌──────────────▼─────────────┐
         │      Execution Engine       │
         │  - Process pool             │
         │  - Test prioritization      │
         │  - Timeout handling         │
         │  - Flaky mitigation         │
         └──────────────┬─────────────┘
                        │
         ┌──────────────▼─────────────┐
         │      Analysis & Scoring     │
         │  - Kill classification      │
         │  - Equiv. heuristics        │
         │  - MSI + MS calculation     │
         │  - Latent mutant tracking   │
         └──────────────┬─────────────┘
                        │
         ┌──────────────▼─────────────┐
         │         Reporter            │
         │  - JSON / HTML / Markdown   │
         │  - GitHub PR Integration    │
         │  - CI/CD artifact export    │
         └─────────────────────────────┘
```

---

## 4. Mutationsoperatoren

### 4.1 Kern-Operatoren (Pflicht, Phase 1)

Die Forschungslage ist hier ungewöhnlich konsistent: Jia & Harman (2010), Papadakis et al. (2017) und beide Google-Paper (2018, 2021) konvergieren auf ein minimales Set von fünf Operatoren, das 90 %+ der Fault-Detection-Kapazität abdeckt.

| ID | Name | Beschreibung | Ruby-Beispiel |
|---|---|---|---|
| **AOR** | Arithmetic Operator Replacement | Ersetzt `+, -, *, /, **, %` durch jeweils andere | `a + b` → `a - b` |
| **LCR** | Logical Connector Replacement | Ersetzt `&&, \|\|` und umkehrt Operanden | `a && b` → `a \|\| b` |
| **ROR** | Relational Operator Replacement | Ersetzt `<, >, <=, >=, ==, !=` und `true/false` | `a > b` → `a >= b` |
| **UOI** | Unary Operator Insertion | Fügt `!, -, +` vor Variablen ein | `n` → `!n`, `-n` |
| **SBR** | Statement Block Removal | Entfernt einzelne Statements | `return x` → _(leer)_ |

> **Empirische Grundlage:** Zhang et al. (2013) zeigen, dass 10 Operatoren aus 43 verfügbaren gleichwertige oder bessere Testeffektivität erzielen. Das 5er-Set ist das destillierte Minimum — erweiterbar, nicht reduzierbar.

### 4.2 Ruby-OO-Operatoren (Phase 2, Ruby-spezifisch)

Ruby ist eine vollständig objektorientierte Sprache. Die OO-Operatoren aus der Java-Literatur (muJava-Subset) müssen Ruby-adäquat adaptiert werden. Sie ergänzen den Phase-1-Kern und werden erst in Phase 2 implementiert, weil sie komplexere AST-Traversal-Logik benötigen und ihr Signal-to-Noise-Verhältnis erst nach empirischer Messung am Phase-1-Basis calibriert werden kann (Analogie: Google brauchte 6 Jahre iterativer Kalibrierung).

| ID | Name | Stryker-kompatibler Name | Beschreibung | Ruby-Beispiel |
|---|---|---|---|---|
| **MCD** | Method Call Deletion | `MethodExpression` (erweitert) | Entfernt einen Methodenaufruf | `obj.save` → _(leer)_ |
| **MRS** | Method Return Substitution | `ReturnValue` (erweitert) | Ersetzt Rückgabewert durch `nil`, `0`, `false` | `def f = calc` → `def f = nil` |
| **IVR** | Instance Variable Reset | _(Ruby-spezifisch)_ | Setzt `@var` auf `nil` | `@count += 1` → `@count = nil` |
| **BLK** | Block Argument Removal | `BlockStatement` (erweitert) | Entfernt `&block`-Übergabe | `map(&method(:f))` → `map` |
| **PMR** | Pattern Match Replacement | `PatternMatch` | Ersetzt Pattern-Match-Arm | `in { x: Integer }` → `in { x: String }` |

> **Phase-1 Light Set (kanonisch):** `ArithmeticOperator`, `EqualityOperator`, `LogicalOperator`, `BooleanLiteral`, `ConditionalExpression`, `StringLiteral`, `ReturnValue`. Diese sieben Operatoren sind in `lib/henitai/operator.rb` als `LIGHT_SET` definiert und bilden den MVP. Die obigen OO-Operatoren gehören zum `FULL_SET` und werden in Phase 2 hinzugefügt.

### 4.3 Stryker-kompatible Operator-Benennung

Wir verwenden die Stryker-Operator-Namen als kanonische Bezeichnung, damit Berichte im Dashboard korrekt dargestellt und gefiltert werden können. Ruby-spezifische Operatoren erhalten neue Namen im Stryker-Stil:

| Unser Operator | Stryker-Name | Status |
|---|---|---|
| AOR | `ArithmeticOperator` | Stryker-kompatibel |
| ROR | `EqualityOperator` | Stryker-kompatibel |
| LCR | `LogicalOperator` | Stryker-kompatibel |
| UOI | `UnaryOperator` | Stryker-kompatibel |
| SBR | `BlockStatement` | Stryker-kompatibel |
| — | `BooleanLiteral` | Stryker-kompatibel |
| — | `StringLiteral` | Stryker-kompatibel |
| — | `ArrayDeclaration` | Stryker-kompatibel |
| — | `AssignmentOperator` | Stryker-kompatibel |
| — | `ConditionalExpression` | Stryker-kompatibel |
| — | `RegexLiteral` | Stryker-kompatibel |
| MRS | `MethodExpression` | Stryker-kompatibel (erweitert) |
| PMR | `PatternMatch` | Ruby-spezifisch (neu) |
| — | `SafeNavigation` | Ruby-spezifisch (neu, `&.`) |
| — | `RangeLiteral` | Ruby-spezifisch (neu, `..`/`...`) |
| — | `HashLiteral` | Ruby-spezifisch (neu) |

### 4.4 Erweiterte Operatoren (Phase 2, optional)

Diese Operatoren sind in der Literatur beschrieben, aber für MVP nicht zwingend:

- **SOM (Second-Order Mutation):** Kombination zweier FOMs nach JudyDiffOp-Strategie (Madeyski et al. 2014). Reduziert äquivalente Mutanten um 65–87 %, aber erhöht Kombinatorik.
- **Performance-Operatoren** (Delgado-Pérez et al. 2010): RCL (Remove Cache Loop), URV (Unnecessary Recalculation Value) — nur relevant wenn Performance-Regression-Tests vorhanden.
- **Ractor-Operatoren:** Entfernung von Synchronisations-Primitiven, Race-Condition-Injektion — für nebenläufigen Ruby-Code.

### 4.4 Operator-Taxonomie und Konfiguration

Das Framework implementiert das **SoMO-Klassifikationsmodell** (Gutiérrez-Madroñal et al. 2014):

```yaml
# Konfiguration via .henitai.yml
mutation:
  operators: light       # light (Phase 1 Default) | full
  sampling:
    ratio: 0.05          # 5 % Sampling für CI (Zhang et al. 2013)
    strategy: stratified # per method, nicht global
  max_mutants_per_line: 1  # Google-Empfehlung (Petrović et al. 2021)
```

**Warnung — Redundanzfalle:** Deng & Offutt (2018) zeigen für Android, dass 3 von 19 Standard-Operatoren vollständig redundant sind (AODU, AOIU, LOI). Für Ruby ist eine analoge Redundanzanalyse nach erster Produktionsphase durchzuführen und das Default-Set entsprechend zu bereinigen.

---

## 5. Kostensenkung (Pflicht-Pipeline)

Die Literatur klassifiziert Kostensenkungsstrategien in sechs Zielkategorien (Pizzoleto et al. 2019 — SLR über 153 Paper). Das Framework implementiert sie in einer priorisierten Kaskade:

### 5.1 Phase-Gate-Architektur

```
Code-Änderung (Git Diff)
        │
        ▼
[Gate 1] Inkrementelle Analyse — nur geänderte Dateien/Methoden
        │  Effekt: 60–80 % Mutanten-Reduktion (RTS-Studie, Chen & Zhang 2018)
        ▼
[Gate 2] Arid-Node-Filterung — nicht-produktive Knoten ausschließen
        │  Effekt: 85 % → 11 % unproduktive Mutanten (Google 2021)
        ▼
[Gate 3] Selektive Mutation — Operator-Subset anwenden
        │  Effekt: 70–90 % Mutanten-Reduktion ohne Qualitätsverlust (Jia & Harman 2010)
        ▼
[Gate 4] Stillborn-Filterung — syntaktisch invalide Mutanten verwerfen
        │  Effekt: eliminiert 5–15 % nutzloser Execution-Versuche
        ▼
[Gate 5] Stratified Sampling — 5 % pro Methode für CI-Modus
        │  Effekt: 93 % Zeitersparnis bei <1 % Qualitätsverlust (Zhang et al. 2013)
        ▼
Verbleibende Mutanten → Execution Engine
```

### 5.2 Arid-Node-Katalog (Ruby-spezifisch)

Arid Nodes sind AST-Knoten, bei denen Mutation mit hoher Wahrscheinlichkeit Äquivalenz erzeugt oder keinen testbaren Effekt hat. Google hat diese Heuristiken in sechs Jahren auf 11 % Fehlerquote optimiert (Petrović et al. 2021).

Für Ruby zu definieren:

```
Logger-Calls:         Rails.logger.*, puts, p, pp, warn
Debugging:            binding.pry, byebug, debugger
Frozen Constants:     CONSTANT = "string".freeze
Default Arguments:    def f(x = nil)  →  nil-Default
Memoization-Pattern:  @var ||= compute_value
Test-Helfer:          let, subject, before, after (RSpec DSL)
Invariante Vergleiche: is_a?, respond_to?, kind_of?
Kapazitäts-Hints:     Array.new(100), Hash.new
```

Diese Liste ist **iterativ zu erweitern** — jeder Mutant, den Entwickler als "nicht relevant" markieren, ist ein Kandidat für einen neuen Arid-Node-Eintrag. Dieser Feedback-Loop ist der wichtigste Mechanismus zur langfristigen Qualitätsverbesserung.

### 5.3 Test-Priorisierung

Das FaMT-System (Zhang et al. 2013) zeigt 17–38 % Execution-Reduktion durch Coverage-basierte Priorisierung:

```ruby
# Priorisierungs-Strategien (konfigurierbar)
class TestPrioritizer
  # C1: Tests nach Häufigkeit der Coverage-Überschneidung mit Mutant
  def coverage_frequency(tests, mutant) ...

  # C2: Tests nach Statement-Position (früher = wahrscheinlicher tötend)
  def statement_position(tests, mutant) ...

  # P2 (adaptiv): Tests die bereits andere Mutanten getötet haben, zuerst
  def adaptive_power(tests, history) ...
end
```

**Empirische Benchmark-Daten** (als Orientierung für Ruby):

| Projekt-Größe | Erwartete MT-Zeit (ohne Opt.) | Mit Gates 1–5 |
|---|---|---|
| < 2.000 LOC | 2–5 Min | < 30 Sek |
| 2.000–10.000 LOC | 15–60 Min | 2–8 Min |
| 10.000–50.000 LOC | 2–8 Std | 15–45 Min |
| > 50.000 LOC | > 8 Std | 1–3 Std (mit Verteilung) |

> **Hinweis:** Ruby ist ~2–3× langsamer als Java bei Test-Execution durch den Interpreter-Overhead. Diese Werte sind entsprechend konservativ hochgerechnet.

---

## 6. Das Equivalent-Mutant-Problem

Dies ist das schwierigste Problem im Mutation Testing. Es ist formal unentscheidbar (Budd & Angluin 1977). Das Framework muss es pragmatisch behandeln — nicht lösen.

### 6.1 Dreistufige Strategie

**Stufe 1 — Vermeidung (vor der Generierung):**
- Arid-Node-Filterung (Abschnitt 5.2) entfernt häufige Äquivalenz-Quellen
- SOM/JudyDiffOp-Strategie reduziert äquivalente Mutanten um 65–87 % (Madeyski et al. 2014)
- Operator-Constraints: Jeder Operator definiert Preconditions, unter denen er angewendet wird

**Stufe 2 — Heuristische Erkennung (nach der Generierung):**
- Basierend auf MEDIC-Framework (Kintis 2016): Statische Daten-Fluss-Muster in SSA-ähnlicher Form
- Neun erkennbare Muster: Use-Def, Use-Ret, Def-Def, Def-Ret und Variationen
- Erkennungsrate: ~50 % der äquivalenten Mutanten automatisch
- `I-EQM`-Klassifikator: Wenn FOM₁ nicht äquivalent → SOM(FOM₁, FOM₂) wahrscheinlich auch nicht

**Stufe 3 — Transparente Kommunikation (im Report):**
```
Mutation Score (MS):  42 / 87 = 48,3 %   (getötet / (gesamt - bestätigt äquivalent))
Mutation Score Indicator (MSI): 42 / 100 = 42 %  (getötet / alle)
Unbekannt äquivalent: ~13 Mutanten (geschätzt 10–15 %)
```

**Warnung:** Das Framework darf niemals einen exakten MS ausweisen, ohne den Äquivalenz-Vorbehalt zu kommunizieren. Bis zu 50 % der lebenden Mutanten können äquivalent sein.

### 6.2 LLM-Integration (Phase 3, optional)

Meta (Foster et al. 2025) zeigt mit ihrem ACH-System: LLM-basierte Äquivalenz-Detektion erreicht mit Preprocessing-Heuristiken 95 % Precision und 96 % Recall.

```ruby
# Optionale Plugin-Schnittstelle
config.equivalence_detector = :llm
config.llm_provider = :claude  # oder :openai, :local
config.llm_confidence_threshold = 0.85
```

Diese Integration ist als **optionales Plugin** zu entwerfen — nicht als Kern-Dependency. Teams ohne API-Zugang müssen das Framework vollständig nutzen können.

---

## 7. Skalierbarkeit & CI/CD-Integration

### 7.1 Ausführungsmodi

```
┌─────────────────────────────────────────────────────┐
│  Modus         │ Trigger      │ Strategie            │
├─────────────────────────────────────────────────────┤
│  dev-fast      │ On-save      │ Gates 1+2+3, kein    │
│                │              │ Sampling, max 50 Mut.│
├─────────────────────────────────────────────────────┤
│  ci-pr         │ Pull Request │ Gates 1–5, 5 %       │
│                │              │ Sampling, max 7/file │
├─────────────────────────────────────────────────────┤
│  ci-nightly    │ Nacht-Build  │ Gates 1–4, 20 %      │
│                │              │ Sampling, Latent-     │
│                │              │ Mutant-Tracking      │
├─────────────────────────────────────────────────────┤
│  full          │ Release      │ Alle Gates, kein     │
│                │              │ Sampling, SOM aktiv  │
└─────────────────────────────────────────────────────┘
```

### 7.2 Git-Integration (Kern-Feature)

Google's wichtigste Architektur-Entscheidung (Petrović et al. 2018): **Changelist-basiert, nicht dateibasiert.** Das Framework analysiert den Diff, nicht die Gesamtcodebase.

```ruby
# Git-Hook-Integration
class GitDiffAnalyzer
  def changed_methods(from: "HEAD~1", to: "HEAD")
    # Gibt exakte Method-Ranges zurück
    # Nur diese werden mutiert
  end

  def coverage_delta
    # Welche Tests decken die geänderten Methoden ab?
    # Basis für Test-Priorisierung
  end
end
```

### 7.3 Flaky-Test-Behandlung

Shi et al. (2019) zeigen: 22 % der Statements haben nicht-deterministische Coverage in Java. Ohne Mitigation landet ~9 % der Mutanten im "unknown"-Status.

```ruby
config.flaky_mitigation = {
  retry_count: 3,          # Schi et al.: 16x ist Maximum; 3x Kompromiss
  isolation: :process,     # Vollständige Prozess-Isolation pro Mutant
  unknown_threshold: 0.05  # Warnung wenn > 5 % Mutanten "unknown"
}
```

### 7.4 GitHub-PR-Integration

Lektion aus Google (Petrović et al. 2021): Mutation Testing wird nur adoptiert, wenn es **im Code-Review-Prozess verankert** ist — nicht als separates Dashboard.

```yaml
# .github/workflows/mutation.yml
- name: Mutation Analysis
  run: bundle exec ruby-mutator analyze --mode ci-pr --format github-review

# Output: Inline-Kommentare im PR für jeden lebenden Mutanten
# Format: "Der Mutant `a + b → a - b` in Zeile 42 wird nicht getötet.
#          Erwäge eine Assertion, die den Rückgabewert prüft."
```

---

## 8. Latente Mutanten & Evolution-Tracking

Dies ist ein Befund aus 2025 (Sohn, Soremekun & Papadakis), der für ein langlebiges Framework besonders relevant ist.

**Definition:** Ein latenter Mutant ist lebendig in Version V, wird aber in Version V+1 ohne explizite Test-Ergänzung getötet — durch Refactoring oder indirekte Test-Änderungen.

**Empirische Befunde:** 3,5 % aller Mutanten über 13 Projekte sind latent. Manifeste Zeit: median 104 Tage. Vorhersage-Accuracy: 86 % via Random Forest.

**Framework-Implikation:** Das Framework speichert den Mutanten-Status versioniert:

```ruby
# Mutanten-Datenbank (persistent, git-tracked)
mutant_db:
  format: sqlite          # leichtgewichtig, git-versionierbar
  tracking:
    - mutant_id
    - first_seen_version
    - status_history      # alive/killed/equivalent pro Commit
    - days_alive
    - predicted_latent    # ML-Flag (Phase 3)
```

Dies ermöglicht **Trend-Reports:** "Diese Methode hat seit 6 Monaten 3 persistente lebende Mutanten — das deutet auf systematisch schwache Assertions hin."

---

## 8a. Von mutant übernommene Konzepte

Die Analyse des mutant-Gems (`mutant_analysis.md`) liefert sieben direkt übertragbare Konzepte, die unabhängig von mutants Lizenz als etablierte Ruby-idiomatische Lösungen gelten:

### 8a.1 Subject-Expression-System

Das Subject-Adressierungsmodell von mutant ist das bisher präziseste für Ruby. Wir übernehmen die Syntax exakt — sie ist intuitiv und deckt alle Anwendungsfälle ab:

```
MyClass#instance_method          # eine Instanzmethode
MyClass.class_method             # eine Klassenmethode
MyClass#                         # alle Instanzmethoden
MyClass.                         # alle Klassenmethoden
MyNamespace*                     # rekursiv alle Klassen im Namespace
descendants:ApplicationController # gesamte Vererbungshierarchie
source:lib/**/*.rb               # dateipfad-basierte Selektion
```

Im JSON-Output wird der Subject-Ausdruck als `id` und Referenz für `coveredBy`/`killedBy`-Test-Links genutzt.

### 8a.2 Insertion via Monkeypatching (Default-Modus)

Mutationen werden nicht als Dateien auf Disk geschrieben. Stattdessen wird der mutierte Code via `Module#define_method` als Monkeypatch in den jeweiligen Fork injiziert. Das eliminiert Dateisystem-IO pro Mutant und lässt den Original-Code unberührt:

```
Ablauf pro Mutant:
1. Fork erstellen
2. Methode via define_method mit mutiertem Inhalt überschreiben
3. Relevante Tests ausführen
4. Ergebnis an Parent zurückgeben
5. Fork endet → Monkeypatch verschwindet automatisch
```

In Phase 2 ersetzt Mutation-Switching diesen Ansatz für den Performance-Modus.

### 8a.3 Longest-Prefix-Match Test-Selektion (RSpec)

Für `Foo::Bar#baz` werden automatisch alle RSpec-Beispielgruppen mit Beschreibungs-Präfix `Foo::Bar#baz`, `Foo::Bar` oder `Foo` ausgewählt — in dieser Prioritätsreihenfolge. Kein explizites Mapping notwendig bei Einhaltung der RSpec-Konvention.

Override via Metadaten für abweichende Konventionen:

```ruby
# Explizites Mapping (mehrere Subjects):
it 'orchestrates creation', mutant_expression: ['UserService#register', 'Mailer#welcome'] do ...

# Ausschluss langsamer Integrationstests:
it 'Full API roundtrip', mutant: false do ...
```

Diese Metadata-Schlüssel werden 1:1 aus mutant übernommen — Teams, die beide Frameworks kennen, müssen nichts umlernen.

### 8a.4 Drei Inline-Direktiven

```ruby
class MyClass
  # henitai:disable
  def generated_method  # gesamte Methode deaktivieren
  end

  # henitai:disable operator=ArithmeticOperator
  def calculate  # nur arithmetische Mutationen deaktivieren
  end

  # henitai:disable reason="auto-generated DSL"
  def dsl_method  # mit Begründung für Reports
  end
end
```

Namespace-weites Ignore gehört in `.henitai.yml`, nicht in Source-Code-Kommentare.

### 8a.5 Metaprogramming-Limitation (explizit dokumentieren)

mutant kann folgende Ruby-Konstrukte nicht mutieren — wir haben dieselbe Grundlimitierung, und wir dokumentieren sie transparent:

- Methoden definiert via `module_eval`, `class_eval`, `define_method`, `define_singleton_method`
- Methoden definiert via `eval`-Strings
- Singleton-Methoden nicht auf Konstante oder `self` definiert

**Unterschied zu mutant:** Wir priorisieren `attr_accessor`, `scope` und häufige Rails-DSL-Patterns für Phase 2 als statisch analysierbare Spezialfälle — mutant behandelt diese nicht.

### 8a.6 Coverage-Kriterien (konfigurierbar)

```yaml
# .henitai.yml
coverage_criteria:
  test_result: true       # Fehlgeschlagene Tests → Kill (Default: true)
  timeout: false          # Timeouts → Kill (Default: false)
  process_abort: false    # Crashes → Kill (Default: false, Vorsicht!)
```

Die `process_abort`-Option ist wichtig: Ein Crash im Test-Prozess kann sowohl ein echter Fehler als auch ein Noop-Kill sein. Default `false` ist die sichere Wahl.

### 8a.7 Arid-Node-Pattern-Sprache

mutants AST-Pattern-Sprache für Ignore-Patterns ist konzeptuell elegant. Wir verwenden stattdessen RuboCops `node_pattern`-Syntax — bereits in der `parser`-Gem-Ökosphäre etabliert und dokumentiert:

```yaml
# .henitai.yml
mutation:
  ignore_patterns:
    - "(send _ {:log :debug :info :warn :error} _)"    # Logger-Calls
    - "(send _ :puts _)"                               # puts
    - "(or-asgn (ivasgn _) _)"                        # @var ||= memoization
    - "(send _ :freeze)"                               # .freeze auf Konstanten
    - "(send {(const nil :Rails)(const nil :pp)} _)"   # Rails.logger.*
```

---

## 8b. Stryker-Ökosystem-Integration

### 8b.1 JSON-Output-Format (Pflicht)

Unser Framework gibt als primären Report-Output das `mutation-testing-report-schema`-JSON aus (Version 3.5.1). Das ist keine optionale Kompatibilitäts-Schicht — es ist das native Format. Alle anderen Reports (HTML, Terminal) werden daraus abgeleitet.

**Schema-Kurzreferenz:**
```json
{
  "schemaVersion": "1.7",
  "thresholds": { "high": 80, "low": 60 },
  "projectRoot": "/pfad/zum/projekt",
  "files": {
    "lib/my_class.rb": {
      "language": "ruby",
      "source": "vollständiger Quellcode",
      "mutants": [
        {
          "id": "abc123",
          "mutatorName": "EqualityOperator",
          "replacement": "age > 18",
          "location": {
            "start": { "line": 5, "column": 5 },
            "end":   { "line": 5, "column": 12 }
          },
          "status": "Survived",
          "coveredBy": ["spec-1", "spec-2"],
          "killedBy": [],
          "static": false
        }
      ]
    }
  }
}
```

**Wichtige Details:** Zeilen/Spalten sind **1-basiert**. Das `source`-Feld muss den vollständigen Dateiinhalt enthalten (wird für Syntax-Highlighting im HTML-Report benötigt).

**Mutant-Status-Werte:** `Killed`, `Survived`, `NoCoverage`, `Timeout`, `CompileError`, `RuntimeError`, `Ignored`, `Pending`

In den Score gehen ein: `Killed` + `Timeout` (detected) vs. `Survived` + `NoCoverage` (undetected). `CompileError`, `RuntimeError`, `Ignored` bleiben außen vor.

### 8b.2 HTML-Report via mutation-testing-elements

Die Web-Component-JS-Datei von `mutation-testing-elements` wird ins Gem gevendort (~500 KB). Ein Ruby-ERB-Template generiert eine standalone HTML-Datei, die das JSON einbettet:

```
lib/
  henitai/
    reporters/
      html_reporter.rb      # ERB-Template-Rendering
    assets/
      mutation-testing-elements.js   # Gevendort, versioniert
    templates/
      report.html.erb               # Wrapper-HTML
```

Das Template injiziert das JSON in das `<mutation-test-report-app>`-Element. Keine Server-Abhängigkeit, öffnet direkt im Browser.

### 8b.3 Stryker Dashboard Reporter

```ruby
# Reporter-Konfiguration in .henitai.yml:
reporters:
  - terminal
  - html
  - json
  - dashboard         # Aktiviert Dashboard-Upload

dashboard:
  project: "github.com/mein-org/mein-repo"   # auto-detect aus git remote
  version: ""         # auto-detect aus CI env vars
  api_key: ""         # via ENV["STRYKER_DASHBOARD_API_KEY"]
  module: ""          # optional, für Monorepos
  base_url: "https://dashboard.stryker-mutator.io"  # self-hosting möglich
```

**Auto-Detection CI-Variablen:**
- GitHub Actions: `GITHUB_REF_NAME`, `GITHUB_REPOSITORY`
- GitLab CI: `CI_COMMIT_REF_NAME`, `CI_PROJECT_PATH`
- Fallback: `git rev-parse --abbrev-ref HEAD`, `git remote get-url origin`

### 8b.4 Mutation-Switching (Phase 2, Performance-Modus)

Stryker4s hat durch dieses Muster die Laufzeit von 40 Minuten auf 40 Sekunden reduziert. Anstatt per Mutant zu forken und neu zu laden, wird die Codebase einmal mit allen Mutanten instrumentiert geladen:

```ruby
# Instrumentierter Code (generiert, nicht von Hand geschrieben):
def adult?(age)
  case ENV.fetch("STRYKER_ACTIVE_MUTANT", nil)
  when "mut_001" then age > 18      # EqualityOperator: >= → >
  when "mut_002" then age <= 18     # EqualityOperator: >= → <=
  when "mut_003" then true          # BooleanLiteral: Bedingung immer wahr
  when "mut_004" then false         # BooleanLiteral: Bedingung immer falsch
  else                age >= 18     # Original
  end
end
```

Pro Mutant wird dann nur noch `STRYKER_ACTIVE_MUTANT=mut_001` gesetzt und die Tests neu gestartet — ohne Re-Load der Codebase.

**Trade-off:** Instrumentierter Code ist schwerer zu debuggen und erhöht Memory-Bedarf proportional zur Mutantenanzahl. Als expliziter `--mode=switching` Opt-in implementieren.

### 8b.5 Worker-Isolation (Stryker-Konvention)

Wir übernehmen die `STRYKER_MUTATOR_WORKER`-Umgebungsvariable exakt:

```ruby
# In jedem Worker-Prozess gesetzt:
ENV["STRYKER_MUTATOR_WORKER"] = worker_index.to_s  # "0", "1", "2", ...

# Hook-Dateien können dann isolieren:
# .henitai/hooks.rb
hooks.register(:worker_process_start) do |index:|
  database_name = "#{base_db_name}_worker_#{index}"
  # Eigene DB pro Worker anlegen...
end
```

---

## 9. Anti-Patterns (explizit verboten)

Diese Entscheidungen sind durch Forschungsevidenz klar negativ — sie dürfen im Framework nicht als Default-Verhalten auftauchen:

**Kein Regex-basiertes Mutieren.** Führt zu 84,5 % Syntaxfehlern (Ivanova & Khritankov 2020). Ausschließlich AST-basiert.

**Kein 100 %-Mutation-Adequacy-Ziel.** Google hat dieses Ziel explizit verworfen (Petrović et al. 2018). Es ist unpraktisch und verleitet zu trivial gefüllten Tests. Der Report soll nie "Ziel: 100 %" kommunizieren.

**Keine Cross-Projekt-Prediction-Modelle.** ML-Modelle für Mutanten-Score generalisieren nicht über Projekt-Grenzen (Jalbert & Bradbury 2012; Zhang et al. 2016 — Accuracy sinkt auf < 30 %). Wenn Predictive Mutation implementiert wird, ausschließlich pro-Projekt trainieren.

**Kein Higher-Order Mutation als Default.** Die Kombinatorik explodiert O(N²), ohne proportionalen Nutzen für MVPs (Jia & Harman 2013). SOM ist als explizites Opt-in verfügbar.

**Keine unkommentierte MSI/MS-Ausgabe.** Der Unterschied zwischen Mutation Score (MS) und Mutation Score Indicator (MSI) muss immer kommuniziert werden. Äquivalenz-Unsicherheit ist Teil des Reports, nicht sein Fehlen.

**Kein Ignorieren von Stillborn Mutants.** Syntaktisch invalide Mutanten müssen vor der Test-Execution gefiltert werden. AST-Validierung ist nicht optional.

---

## 10. Implementierungsroadmap

### Phase 1 — MVP (Kern-Pipeline)

Ziel: Ein funktionierendes Framework, das auf einem mittelgroßen Ruby-Projekt (< 10.000 LOC) in < 10 Minuten läuft und sofort Stryker-Dashboard-kompatiblen Output produziert.

- [ ] AST-Parser-Integration (`parser` Gem, `unparser` für Code-Rekonstruktion)
- [ ] Dry-Run Phase (Baseline-Verifikation vor Mutation)
- [ ] **Light Set (7 Operatoren):** `ArithmeticOperator`, `EqualityOperator`, `LogicalOperator`, `BooleanLiteral`, `ConditionalExpression`, `StringLiteral`, `ReturnValue` — definiert als `Henitai::Operator::LIGHT_SET` in `lib/henitai/operator.rb`
- [ ] Stillborn-Filterung → Status `CompileError` (Stryker-kompatibel)
- [ ] Process-basierte parallele Test-Execution (`STRYKER_MUTATOR_WORKER` Env-Variable)
- [ ] RSpec-Integration (Longest-Prefix-Match Test-Selektion)
- [ ] Minitest-Integration
- [ ] **`mutation-testing-report-schema` JSON-Output** (Pflicht, 1-basierte Zeilen/Spalten)
- [ ] Terminal-Report (abgeleitet aus JSON)
- [ ] **HTML-Report via gevendortem mutation-testing-elements** (standalone, kein Server)
- [ ] Git-Diff-basierte Inkrementalität (Gate 1, `--since git-reference`)
- [ ] Einfacher Arid-Node-Katalog (50–100 Ruby-Patterns, AST-Pattern-Syntax)
- [ ] Timeout-Handling → Status `Timeout` (Stryker-kompatibel)
- [ ] Static Mutant Detection (`static: true` im JSON)
- [ ] `.henitai.yml` Konfigurations-Schema
- [ ] `# henitai:disable` Inline-Direktive

### Phase 2 — Production-Ready

Ziel: CI/CD-fähig, Developer-Feedback-Loop, 85 % Zeitersparnis gegenüber Naive.

- [ ] **Stryker Dashboard Reporter** (PUT-API, Badge-URL, Auto-Detect CI-Vars)
- [ ] Per-Test-Coverage-Analyse (SimpleCov-Integration → 40–60 % Speedup)
- [ ] Stratified Sampling (5 % per Methode, konfigurierbar)
- [ ] Coverage-basierte Test-Priorisierung (C1/C2-Strategien)
- [ ] Erweiterter Arid-Node-Katalog (iterativ via Developer-Feedback)
- [ ] GitHub-PR-Inline-Integration
- [ ] Flaky-Test-Mitigation (Retry, Isolation, `Unknown`-Status)
- [ ] Inkrementeller Snapshot (`henitai-incremental.json`)
- [ ] Selektive Mutation (Operator-Subset-Konfiguration, `mutatorName`-Ignore)
- [ ] Mutanten-Datenbank (SQLite, versioniert — für Latent-Mutant-Tracking)
- [ ] MEDIC-ähnliche Äquivalenz-Heuristiken → `Ignored`-Status im JSON
- [ ] CI-Ausführungsmodi (dev-fast, ci-pr, ci-nightly, full)
- [ ] Hook-System (8 Lifecycle-Hooks, Rails/PostgreSQL-Isolation-Beispiel)
- [ ] Ruby-spezifische Operatoren: `PatternMatch`, `RangeLiteral`, `HashLiteral`, `ArrayDeclaration`

### Phase 3 — Erweiterungen

Ziel: Industrielle Skalierung, LLM-Integration, adaptive Strategien.

- [ ] **Mutation-Switching Performance-Modus** (einmalige Instrumentierung, ENV-basierte Aktivierung)
- [ ] Sentinel-ähnliche adaptive Operator-Selektion (Meta-Heuristik)
- [ ] LLM-Plugin für Äquivalenz-Detektion → `Ignored`-Status (optional)
- [ ] Latente Mutanten-Tracking + ML-Prediction (Sohn et al. 2025)
- [ ] Verteilte Ausführung (Cluster-aware)
- [ ] SOM/JudyDiffOp-Strategie
- [ ] Performance-Operatoren (Opt-in)
- [ ] Ractor-Concurrency-Operatoren
- [ ] Plugin-API für domänenspezifische Erweiterungen
- [ ] Self-Hosted Stryker Dashboard Support

---

## 11. Offene Forschungsfragen

Diese Fragen sind durch die Literatur nicht abschließend beantwortet und müssen durch eigene Experimente mit dem Framework beantwortet werden:

**F1: Operator-Redundanz für Ruby.** Die 5er-Kern-Menge ist für Java/C empirisch validiert. Für Ruby (dynamisch typisiert, OO-first) ist eine eigene Redundanzanalyse notwendig. Deng & Offutt (2018) zeigen für Android, dass 3 von 19 Operatoren vollständig redundant sind — das Verhältnis dürfte für Ruby anders sein.

**F2: Arid-Node-Effektivität im Ruby-Ökosystem.** Google hat 6 Jahre gebraucht, um 11 % Fehlerquote zu erreichen. Wie lange dauert das für Ruby mit seinen idiomatischen Patterns (Metaprogramming, DSLs wie Rails)?

**F3: Coupling Hypothesis für Ruby.** Die Grundannahme des Mutation Testings — Tests, die FOMs töten, töten auch komplexere Faults — ist für Java vielfach bestätigt (Jia & Harman 2010). Für dynamisch typisierte Sprachen mit Duck Typing ist diese Übertragbarkeit nicht gesichert.

**F4: LLM-Äquivalenz-Erkennung für Ruby.** Meta (Foster et al. 2025) validiert diese Technik für Kotlin/Android. Ruby-spezifische Auswertung fehlt — insbesondere für Metaprogramming-Code, bei dem die Semantik schwer zu formalisieren ist.

**F5: Latente Mutanten in dynamischen Sprachen.** Das Latent-Mutant-Konzept (Sohn et al. 2025) ist an Java-Projekten validiert. Ruby-Projekte mit häufigem Refactoring (Rails-Ökosystem) könnten signifikant andere Latenz-Profile zeigen.

---

## 12. Literaturgrundlage (Auswahl nach Framework-Relevanz)

**Fundament:**
- Jia & Harman (2010) — "An Analysis and Survey of the Development of Mutation Testing" — *Hoch*
- Papadakis et al. (2017) — "Mutation Testing Advances: An Analysis and Survey" — *Hoch*

**Operatoren & Taxonomie:**
- Gutiérrez-Madroñal et al. (2014) — "Mutation Testing Guideline and Mutation Operator Classification" — *Hoch*
- Deng & Offutt (2018) — "Reducing the Cost of Android Mutation Testing" — *Mittel*

**Kostensenkung:**
- Zhang et al. (2013) — "Operator-Based and Random Mutant Selection: Better Together" — *Hoch*
- Zhang et al. (2013) — "Faster Mutation Testing Inspired by Test Prioritization" — *Hoch*
- Pizzoleto et al. (2019) — "A Systematic Literature Review of Techniques and Metrics to Reduce the Cost of Mutation Testing" — *Hoch*

**Äquivalenz:**
- Madeyski et al. (2014) — "Overcoming the Equivalent Mutant Problem" — *Hoch*
- Kintis et al. (2016) — "Effective Methods to Tackle the Equivalent Mutant Problem" — *Hoch*

**Industrieerfahrung (Google):**
- Petrović & Ivanković (2018) — "State of Mutation Testing at Google" — *Hoch*
- Petrović et al. (2021) — "Practical Mutation Testing at Scale: A View from Google" — *Hoch*
- Petrović et al. (2021) — "Does Mutation Testing Improve Testing Practices?" — *Hoch*

**Aktuelle Trends:**
- Foster et al. (2025) — "Mutation-Guided LLM-based Test Generation at Meta" — *Mittel*
- Sohn et al. (2025) — "Latent Mutants: A Large-Scale Study on the Interplay between Mutation Testing and Software Evolution" — *Mittel*
- Sánchez et al. (2022) — "Mutation Testing in the Wild: Findings from GitHub" — *Mittel*

---

*Vollständige Zusammenfassungen aller 39 Referenzpaper: `/summaries/`*
