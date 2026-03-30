# Analyse: mutant-Gem — Konzepte, Lücken und Ableitungen
## Basis für unser eigenes Ruby-4-Framework

> **Quelle:** Ausschließlich öffentliche Dokumentation (README, /docs/*, Meta-Verzeichnis-Struktur)
> **Lizenz-Hinweis:** Kein Code wurde kopiert oder adaptiert. Nur Konzepte und Design-Entscheidungen werden dokumentiert.
> **Stand:** März 2026

---

## 1. Was mutant ist — und was nicht

mutant ist das einzige etablierte Ruby-Mutation-Testing-Framework mit relevanter GitHub-Adoption (296 Repos laut Sánchez et al. 2022). Es ist seit ~2012 in aktiver Entwicklung, IEEE-veröffentlicht und im Trail-of-Bits Ruby Security Field Guide referenziert. Die kommerzielle Lizenz ($30/Monat pro Entwickler) ist der Hauptgrund, weshalb wir ein eigenes Framework entwickeln.

Interessanter architektonischer Befund aus dem Repo: mutant hat eine **Rust-Komponente** (`Cargo.toml`, `rust-toolchain.toml`). Das deutet auf eine Verlagerung performance-kritischer Teile in Rust hin — ein Hinweis auf die bekannten Performance-Grenzen rein Ruby-basierter Implementierungen.

---

## 2. Konzepte, die wir übernehmen sollten

### 2.1 Das Subject-Modell

**Kernkonzept:** Ein *Subject* ist eine adressierbare Einheit für Mutation Testing. mutant unterstützt explizit Instance Methods und Singleton (Class) Methods als primäre Subjects.

**Warum das gut ist:** Die Granularität auf Methoden-Ebene ist der richtige Ausgangspunkt. Sie ermöglicht präzise Test-Selektion (nur Tests für diese Methode laufen) und macht Reports actionierbar (du siehst genau, welche Methode nicht abgedeckt ist).

**Für unser Framework:** Subject-Adressierung mit einem klaren Expression-System:
```
MyNamespace::MyClass#instance_method      # Instanzmethode
MyNamespace::MyClass.class_method         # Klassenmethode
MyNamespace::MyClass#                     # alle Instanzmethoden
MyNamespace::MyClass*                     # rekursiv alle Subjects
descendants:ApplicationController        # Vererbungshierarchie
source:lib/**/*.rb                        # dateipfad-basierte Selektion
```
Das ist ein gut durchdachtes, konsistentes Expression-Modell. Wir sollten dieselbe Syntax übernehmen — sie ist intuitiv und deckt alle üblichen Anwendungsfälle ab.

---

### 2.2 Operator-Organisation nach AST-Knoten-Typ

**Kernkonzept:** mutant organisiert seine 79 Operatoren-Definitionen **nach AST-Knoten-Typ** (`if.rb`, `send.rb`, `and.rb`, `while.rb`, etc.), nicht nach abstrakt-semantischer Kategorie (AOR, LCR, etc.).

Die vollständige Liste der abgedeckten Node-Typen:
`and`, `and_asgn`, `array`, `begin`, `block`, `block_pass`, `blockarg`, `break`, `case`, `case_match`, `casgn`, `cbase`, `class`, `complex`, `const`, `const_pattern`, `csend`, `cvar`, `cvasgn`, `date`, `def`, `defined?`, `dstr`, `dsym`, `ensure`, `false`, `float`, `guard`, `gvar`, `gvasgn`, `hash`, `if`, `index`, `indexasgn`, `int`, `ivar`, `ivasgn`, `kwarg`, `kwbegin`, `kwoptarg`, `lambda`, `lvar`, `lvasgn`, `masgn`, `match_current_line`, `match_pattern_p`, `module`, `next`, `nil`, `nthref`, `numblock`, `op_asgn`, `or`, `or_asgn`, `procarg_zero`, `range`, `rational`, `redo`, `regexp`, `rescue`, `return`, `sclass`, `self`, `send`, `str`, `super`, `sym`, `true`, `until`, `until_post`, `while`, `while_post`, `xstr`, `yield`, `zsuper`

**Warum das gut ist:** Die Organisations-Einheit "AST-Knoten" ist natürlicher als die akademische Taxonomie (AOR, LCR etc.), weil sie direkt auf die Implementierungsstruktur passt. Wenn du einen `if`-Knoten traversierst, weißt du sofort welche Mutationen möglich sind.

**Für unser Framework:** Denselben Ansatz verwenden — Operator-Module nach AST-Knoten-Typ, nicht nach semantischer Kategorie. Die akademische Taxonomie (AOR, LCR, ROR...) verwenden wir für *Dokumentation und Reporting*, aber die interne Struktur folgt dem AST.

```ruby
# Konzeptuelle Struktur (kein mutant-Code):
module Operators
  module Send     # Für s(:send, receiver, :method_name, args...)
    # Mutation: Methoden-Selektor ersetzen, Receiver entfernen, etc.
  end
  module If       # Für s(:if, condition, then_branch, else_branch)
    # Mutation: Condition negieren, Branches tauschen, etc.
  end
  module And      # Für s(:and, left, right)
    # Mutation: && → ||, left allein, right allein, etc.
  end
end
```

---

### 2.3 Drei semantische Operator-Klassen

**Kernkonzept:** mutant klassifiziert alle Mutationen in drei Klassen:

- **Semantic Reduction:** Vereinfacht den Code (z.B. Statement entfernen, `if x then y else z end` → `y`). Hypothesis: Wenn der Test das nicht bemerkt, war das Statement redundant.
- **Orthogonal Replacement:** Ersetzt eine Semantik durch eine andere (`+` → `-`, `&&` → `||`). Hypothesis: Der Test prüft die spezifische Semantik.
- **Noop (Neutral):** Mutation die konzeptionell keine Verhaltensänderung bewirkt. Wird als Sanity-Check verwendet — wenn ein Noop-Mutant Tests bricht, ist etwas mit der Test-Umgebung falsch.

**Warum das gut ist:** Die Noop-Klasse ist besonders clever — sie fungiert als automatischer Gesundheitscheck der Test-Infrastruktur. Wenn ein Noop getötet wird, liegt ein Problem in der Isolation oder im Test-Setup vor.

**Für unser Framework:** Alle drei Klassen implementieren. Noops explizit als `coverage_criteria`-Konfiguration exponieren:

```yaml
coverage_criteria:
  noop: true          # Noops als Abdeckungs-Nachweis werten (Default: false)
  timeout: false      # Timeouts als Kill werten (Default: false)
  process_abort: false  # Crashes als Kill werten (Default: false)
  test_result: true   # Fehlgeschlagene Tests als Kill werten (Default: true)
```

---

### 2.4 Insertion via Monkeypatching

**Kernkonzept:** Mutationen werden nicht als neue Dateien auf Disk geschrieben. Stattdessen wird der mutierte Code zur Laufzeit via dynamisch erstellte Monkeypatches in die Ruby-Runtime injiziert.

**Warum das gut ist:**
- Keine temporären Dateien, die koordiniert werden müssen
- Kein Dateisystem-IO für jede Mutation
- Funktioniert nahtlos mit dem Ruby-Require-System
- Der originale Code auf Disk bleibt unverändert

**Wichtige Einschränkung:** Isolation bleibt trotzdem notwendig, weil Monkeypatches globalen State verändern. Deshalb wird jede Mutation in einem Fork ausgeführt — der Monkeypatch "lebt" nur im Child-Prozess.

**Für unser Framework:** Denselben Ansatz verwenden. Die Alternative (Dateien schreiben + neu requiren) ist langsamer und fehleranfälliger. Konzept:

```
1. Originale Methode in Ruby-Object-Space per `Module#define_method` überschreiben
2. Neue (mutierte) Implementierung injizieren
3. Tests laufen lassen (im geforkten Prozess)
4. Prozess endet → Monkeypatch verschwindet automatisch
```

---

### 2.5 Fork-basierte Isolation

**Kernkonzept:** Für jeden zu testenden Mutanten wird ein eigener POSIX-Prozess geforkt. Der Child-Prozess trägt die Mutation und läuft die relevanten Tests. Der Parent-Prozess koordiniert und sammelt Ergebnisse.

Dies löst elegant mehrere Probleme gleichzeitig:
- Kein Global-State-Leak zwischen Mutanten
- Crashes (Segfaults) töten nur den Child, nicht den Orchestrator
- Thread-Unsicherheit in Test-Frameworks ist irrelevant (jeder Fork ist single-threaded)
- Abnormale Termination kann explizit als Kill-Kriterium konfiguriert werden

**Für unser Framework:** `Process.fork` ist das richtige Modell. Die Entscheidung, ob Crashes als "Kill" oder "Unknown" gewertet werden, sollte konfigurierbar sein (wie in mutant).

---

### 2.6 Test-Selektion via Longest Prefix Match

**Kernkonzept:** Für einen Subject `Foo::Bar#baz` wählt mutant automatisch alle RSpec-Beispielgruppen aus, deren Beschreibung mit `Foo::Bar#baz`, `Foo::Bar` oder `Foo` beginnt — in dieser Prioritätsreihenfolge.

**Eleganz dieses Ansatzes:** Kein explizites Mapping zwischen Tests und Code notwendig. Die RSpec-Konvention (Beispielgruppen heißen nach der getesteten Klasse/Methode) reicht aus. Nur wenn diese Konvention nicht passt, ist explizites Mapping via `:mutant_expression`-Metadata nötig.

**Für unser Framework:** Denselben Mechanismus implementieren. Zusätzlich die explizite Mapping-Möglichkeit als Opt-in:

```ruby
# RSpec-Konvention (kein Setup nötig):
RSpec.describe Foo::Bar do
  describe '#baz' do
    it '...' # automatisch für Foo::Bar#baz ausgewählt
  end
end

# Explizites Override (für abweichende Konventionen):
it 'orchestriert mehrere Subjects', mutant_expression: ['Foo::Bar#baz', 'Baz::Qux#call'] do
  # ...
end

# Ausschluss von langsamen Tests:
it 'External-API Roundtrip', mutant: false do
  # wird nicht für Mutation-Kill verwendet
end
```

---

### 2.7 Das AST-Pattern-System für Arid Nodes

**Kernkonzept:** mutant hat eine eigene Mini-Sprache für AST-Pattern-Matching — beschrieben als "CSS für AST-Patterns". Diese wird primär für `ignore_patterns` verwendet (welche Code-Stellen nicht mutiert werden sollen).

Beispiel-Syntax:
```
send{selector=(log,info)}                    # jeden log/info-Aufruf ignorieren
send{selector=log receiver=send{selector=logger}}  # nur logger.log ignorieren
block{receiver=send{selector=log}}           # logger.log { "msg" } ignorieren
```

**Warum das gut ist:** Deutlich ausdrucksstärker als einfache String-Patterns oder Regex. Erlaubt präzise Definition von Arid-Nodes ohne False-Positives. Jeder Nutzer kann eigene Patterns definieren, ohne Framework-Code anzufassen.

**Für unser Framework:** Dasselbe Konzept, aber mit Ruby-nativer Syntax. Anstatt einer eigenen DSL könnten wir RuboCop's `node_pattern` verwenden — das ist bereits in der `parser`-Gem-Ökosphäre etabliert:

```ruby
# Konzept: Arid-Node-Definition via node_pattern (RuboCop-kompatibel)
ignore_patterns:
  - "(send _ {:log :info :warn :error} _)"   # logger.*-Calls
  - "(send _ :puts _)"                        # puts-Calls
  - "(ivasgn _ (or-asgn ...))"               # @var ||= pattern
```

---

### 2.8 Das Hook-System

**Kernkonzept:** mutant definiert 8 Lifecycle-Hooks:

```
env_infection_pre / env_infection_post        # vor/nach Code-Loading
setup_integration_pre / setup_integration_post # vor/nach Test-Framework-Setup
mutation_insert_pre / mutation_insert_post     # vor/nach Mutations-Injektion
mutation_worker_process_start                  # wenn Worker-Prozess startet
test_worker_process_start                      # wenn Test-Worker startet
```

**Warum das gut ist:** Das Hook-System löst das Database-Isolation-Problem elegant — pro Worker-Prozess kann eine separate Test-Datenbank erstellt werden. Ohne diesen Hook wäre Rails-Unterstützung praktisch unmöglich.

**Für unser Framework:** Denselben Ansatz — 8 Hooks sind ausreichend. Die Hook-Konfiguration via YAML-Datei (Pfade zu Ruby-Hook-Dateien) ist clean und erweiterbar.

---

### 2.9 Inkrementelle Analyse via `--since`

**Kernkonzept:** `--since git-reference` nutzt `git diff`, um Subjects zu filtern. Ein Subject wird nur ausgewählt, wenn `git diff` einen Hunk meldet, der sich mit der Zeilennummer des Subjects überschneidet.

**Bekannte Limitation:** Nur direkte Änderungen werden erfasst. Wenn eine Konstante geändert wird, die das Verhalten einer Methode beeinflusst, wird die Methode nicht ausgewählt. mutant dokumentiert, dass "more fine-grained tracing is underway".

**Für unser Framework:** Denselben Git-Diff-basierten Ansatz. Die Limitation ist akzeptabel für Phase 1. In Phase 2 können wir Constant-Tracing ergänzen.

---

### 2.10 Konfiguration via `.mutant.yml`

**Kernkonzept:** Drei Konfigurationsmethoden mit klarer Priorität: Inline-Kommentare (`# mutant:disable`) < Config-Datei < CLI-Flags.

**Besonders gut:** `mutant:disable`-Kommentare direkt im Source-Code sind der richtige Mechanismus für einzelne Methoden. Namespace-weites Ignore gehört in die Config-Datei.

**Für unser Framework:** Dieselbe Drei-Ebenen-Hierarchie, aber mit erweitertem Inline-System:

```ruby
# mutant:disable                    # gesamte Methode deaktivieren
# mutant:disable operator=AOR       # nur arithmetische Mutationen deaktivieren
# mutant:disable reason="generated" # mit Begründung (für Reports)
```

---

## 3. Wo mutant Lücken hat — unsere Chancen

### 3.1 Kein maschinenlesbarer Output (OSS)

mutant erzeugt in der OSS-Version **keinen JSON- oder maschinenlesbaren Report**. Das ist explizit dokumentiert: *"A reporter producing a machine readable report does not exist in the OSS version at the time of writing."*

**Unsere Chance:** Von Anfang an JSON, HTML und Markdown als First-Class-Output-Formate. Das ermöglicht CI/CD-Integration, Trend-Tracking über Zeit und GitHub-PR-Kommentare — alles Dinge, die für industrielle Adoption entscheidend sind (vgl. Google-Papers).

---

### 3.2 Kein Sampling und keine Kostensenkungsstrategien

mutant hat **keine Sampling-Modi**, keine Test-Priorisierung und keine selektive Operator-Selektion. Es gibt zwei Operator-Sets (`light` vs. `full`), aber kein systematisches Kostenmanagement.

**Unsere Chance:** Die gesamte Phase-Gate-Pipeline aus unserem Architektur-Dokument (Abschnitt 5) ist ein starkes Differenzierungsmerkmal — insbesondere für große Rails-Projekte, wo mutant oft zu langsam ist.

---

### 3.3 Metaprogramming-Blindheit

mutant **kann folgende Ruby-Konstrukte nicht mutieren:**
- `module_eval`/`class_eval`-definierte Methoden
- `define_method`-Lambdas
- `define_singleton_method`
- `eval`-basierte Methoden-Definition

Das ist eine erhebliche Limitation für Rails-Projekte, die heavily auf Metaprogramming setzen (`attr_accessor`, `scope`, DSL-Methoden, Concerns).

**Unsere Chance:** Zumindest `attr_accessor` und häufige Metaprogramming-Patterns könnten durch spezialisierte Operatoren abgedeckt werden — z.B. durch statische Analyse des Metaprogramming-Aufrufs statt der generierten Methode.

---

### 3.4 Minitest-Integration ist Second-Class

RSpec hat "Longest Prefix Match" out-of-the-box. Minitest braucht manuelle Metadata-Annotation. Das hat historische Gründe (Minitest fehlt RSpec's hierarchische Beispielgruppen-Struktur).

**Unsere Chance:** Eine clevere Minitest-Integration, die Test-Klassen-Namen und -Methoden-Namen für Auto-Mapping nutzt, könnte die Erfahrung signifikant verbessern.

---

### 3.5 Keine CI-Modi / Execution-Budgets

mutant bietet keine konfigurierbaren Ausführungsmodi (dev-fast, ci-pr, nightly, full). Es gibt `--fail-fast` und `--jobs`, aber kein Time-Budgeting.

**Unsere Chance:** Die vier Modi aus unserem Architektur-Dokument (Abschnitt 7.1) sind ein starkes Feature für Teams, die mutant wegen CI-Laufzeiten nicht einsetzen können.

---

### 3.6 Kein Latent-Mutant-Tracking

Kein Persistenz-Modell, keine Mutanten-Datenbank, kein historisches Tracking. Jeder Lauf ist stateless.

**Unsere Chance:** Evolution-Tracking (vgl. Sohn et al. 2025) ist ein Alleinstellungsmerkmal, das für langlebige Projekte hochrelevant ist.

---

### 3.7 Keine Äquivalenz-Heuristiken

mutant ignoriert das Equivalent-Mutant-Problem vollständig — es gibt keine automatische Erkennung. Alle lebenden Mutanten werden gleich behandelt, ohne Hinweis darauf, welche möglicherweise äquivalent sind.

**Unsere Chance:** Selbst einfache Heuristiken (Arid-Node-Filtering nach Google-Muster, MEDIC-ähnliche Datenfluss-Patterns) wären bereits ein Fortschritt.

---

## 4. Was wir explizit anders machen

### 4.1 Architectural Decision: Rust vs. Pure Ruby

mutant hat offensichtlich begonnen, performance-kritische Teile nach Rust auszulagern. Wir bleiben für Phase 1 bei Pure Ruby — mit dem Ziel, Process-basierte Parallelität für Performance zu nutzen. Sollte sich Rust als notwendig erweisen, ist das eine Phase-3-Entscheidung.

### 4.2 Keine kommerzielle Lizenz

Wir wählen eine permissive Open-Source-Lizenz (MIT oder Apache 2.0), um breiteren Adoption zu ermöglichen. Der GitHub-Survey (Sánchez et al. 2022) zeigt: Die tools mit den meisten Adopters sind alle Open Source.

---

## 5. Vorgehensweise: Wie wir vorgehen

### Schritt 1 — Konzept-Verifikation (vor dem Coden)

Bevor wir die erste Zeile schreiben, sollten wir das Konzept an einem Minimal-Beispiel validieren:

1. Eine einfache Ruby-Klasse (20 LOC, eine Methode)
2. Manuell den `parser`-Gem verwenden, um den AST zu lesen
3. Manuell eine Mutation im AST vornehmen (z.B. `>=` → `>`)
4. Den mutierten AST via `unparser` zurück zu Code
5. Den Code via Monkeypatch injizieren und einen RSpec-Test laufen lassen

Dieser Spike dauert ~2h und validiert die gesamte Core-Loop.

### Schritt 2 — Subject-Registrierung und AST-Traversal

Implementierung der Subject-Discovery: Alle Methoden in einem Ruby-Modul/einer Klasse finden, ihre Quellcode-Positionen (Zeile + Datei) ermitteln. Basis: `ObjectSpace` + `Method#source_location`.

### Schritt 3 — Erste 5 Operatoren

In dieser Reihenfolge (nach Complexity und Wert):
1. `SBR` (Statement Block Removal) — einfachster Operator, höchster Wert für Test-Lücken
2. `ROR` (Relational Operator Replacement) — deckt häufigste Boundary-Fälle ab
3. `AOR` (Arithmetic Operator Replacement) — straightforward AST-Transformation
4. `LCR` (Logical Connector Replacement) — `and`/`or`-Knoten
5. `MRS` (Method Return Substitution) — Ruby-spezifisch, hoher Wert

### Schritt 4 — Fork-Isolation + RSpec-Integration

Process.fork-basierte Isolation + Longest-Prefix-Match Test-Selektion für RSpec.

### Schritt 5 — JSON-Report + `.mutant.yml` Config

Erst wenn das Kern-System stabil ist: maschinenlesbarer Output und Konfigurationsformat.

---

## 6. Namensvorschlag und Positionierung

**Positionierung gegenüber mutant:**
- Open-Source (MIT/Apache) → kein kommerzieller Lock-in
- Kostensenkung als First-Class-Feature → auch für große Codebases praktikabel
- Maschinenlesbarer Output → CI/CD-native
- Metaprogramming-Support → besser für Rails

**Name:** Noch offen — aber der Name sollte *nicht* mit "mutant" oder "mutation" beginnen (Verwechslungsgefahr). Etwas wie `spectre`, `proban`, `killfeed` oder `kagemushi` (影虫 — "Shadow Bug") wäre differenzierend.

---

*Quellen: ausschließlich https://github.com/mbj/mutant — README, /docs/*, meta/-Verzeichnis-Struktur*
