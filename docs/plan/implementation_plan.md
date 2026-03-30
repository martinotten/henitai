# Henitai 変異体 — Implementierungsplan

> **Version:** 0.1 · **Stand:** März 2026
> **Zielplattform:** Ruby 4.0.2 · **Gem:** `henitai`
> **Basis:** [architecture.md](architecture.md), 39 Paper (1992–2025), mutant- und Stryker-Analyse

---

## Inhaltsverzeichnis

1. [Architektur-Überblick](#1-architektur-überblick)
2. [Komponentenmodell](#2-komponentenmodell)
3. [Datenfluß durch die Pipeline](#3-datenfluß-durch-die-pipeline)
4. [Implementierungsphasen](#4-implementierungsphasen)
   - [Phase 1 — Fundament (MVP)](#phase-1--fundament-mvp)
   - [Phase 2 — Produktionsreife](#phase-2--produktionsreife)
   - [Phase 3 — Ökosystem & Intelligenz](#phase-3--ökosystem--intelligenz)
5. [Task-Breakdown](#5-task-breakdown)
6. [Technische Entscheidungen (ADRs)](#6-technische-entscheidungen-adrs)
7. [Qualitätskriterien](#7-qualitätskriterien)
8. [Risiken & Mitigationen](#8-risiken--mitigationen)

---

## 1. Architektur-Überblick

Henitai ist ein **AST-basiertes Mutation-Testing-Framework** für Ruby 4. Die Architektur folgt vier Designprinzipien (vollständig begründet in `architecture.md`):

- **Aktionierbarkeit vor Vollständigkeit** — Kein Mutant ohne Signal für den Entwickler
- **Kosten sind Kern, nicht Option** — Phase-Gate-Pipeline als Pflicht-Pipeline
- **Erweiterbarkeit durch Schichten** — Plugin-Punkte für Operatoren, Reporter, Integrationen
- **Ökosystem-Kompatibilität** — Stryker-JSON-Schema als natives Ausgabeformat

### Systemgrenzen

```
┌──────────────────────────────────────────────────────────────────┐
│  Developer / CI                                                   │
│                                                                   │
│  $ bundle exec henitai run --since origin/main 'MyClass#method'  │
└──────────────────────────────┬───────────────────────────────────┘
                               │
┌──────────────────────────────▼───────────────────────────────────┐
│  Henitai (dieser Gem)                                             │
│                                                                   │
│  ┌─────────┐   ┌──────────┐   ┌──────────┐   ┌───────────────┐  │
│  │   CLI   │→  │  Runner  │→  │ Pipeline │→  │  Reporters    │  │
│  └─────────┘   └──────────┘   └──────────┘   └───────────────┘  │
└──────────────────────────────────────────────────────────────────┘
         │                                              │
         ▼                                              ▼
  Ruby-Quellcode                           JSON / HTML / Dashboard
  RSpec-Tests                              Terminal-Summary
  .henitai.yml                        Exit-Code für CI
```

---

## 2. Komponentenmodell

### 2.1 Komponentenübersicht

```
lib/henitai/
├── cli.rb                  # Einstiegspunkt (OptionParser)
├── configuration.rb        # YAML-Konfig + Defaults
├── subject.rb              # Adressierbarer Code-Bereich
├── mutant.rb               # Einzelne Mutation + Status
├── operator.rb             # Basisklasse für Operatoren
├── operators/              # Konkrete Operator-Implementierungen
│   ├── arithmetic_operator.rb
│   ├── equality_operator.rb
│   ├── logical_operator.rb
│   ├── boolean_literal.rb
│   ├── conditional_expression.rb
│   ├── string_literal.rb
│   ├── return_value.rb
│   ├── safe_navigation.rb
│   ├── range_literal.rb
│   ├── hash_literal.rb
│   ├── pattern_match.rb
│   ├── array_declaration.rb
│   ├── block_statement.rb
│   ├── method_expression.rb
│   └── assignment_expression.rb
├── runner.rb               # Pipeline-Orchestrator
├── pipeline/               # Phase-Gate-Implementierungen
│   ├── subject_resolver.rb     # Gate 1
│   ├── mutant_generator.rb     # Gate 2
│   ├── static_filter.rb        # Gate 3
│   ├── execution_engine.rb     # Gate 4
│   └── result_collector.rb     # Gate 5
├── integration/            # Test-Framework-Anbindungen
│   ├── base.rb
│   └── rspec.rb
├── reporter/               # Ausgabe-Backends
│   ├── base.rb
│   ├── terminal.rb
│   ├── json.rb
│   ├── html.rb
│   └── dashboard.rb
├── result.rb               # Aggregat + Stryker-Serialisierung
└── version.rb
```

### 2.2 Abhängigkeitsgraph

```
CLI
 └─→ Configuration
 └─→ Runner
       └─→ Pipeline::SubjectResolver  (nutzt: parser, git)
       └─→ Pipeline::MutantGenerator  (nutzt: Operators, AridFilter)
       └─→ Pipeline::StaticFilter     (nutzt: Configuration, Coverage)
       └─→ Pipeline::ExecutionEngine  (nutzt: Integration, Process.fork)
       └─→ Pipeline::ResultCollector  (nutzt: Result, Reporters)
```

Alle Pipeline-Komponenten sind **zustandslos** — sie erhalten Eingabe, geben Ausgabe, kein globaler Zustand. Der Runner hält den Pipeline-Zustand zwischen den Gates.

### 2.3 Schlüsseldatenstrukturen

#### `Subject`
Repräsentiert eine adressierbare Einheit vor der Mutation.

```ruby
Subject = Data.define(
  :namespace,      # "Foo::Bar"
  :method_name,    # "my_method" | nil (Wildcard)
  :method_type,    # :instance | :class
  :source_file,    # "/path/to/foo/bar.rb"
  :source_range,   # 42..68 (Zeilen)
  :ast_node        # Parser::AST::Node
)
```

#### `Mutant`
Repräsentiert eine konkrete Mutation und ihren Ausführungsstatus.

```ruby
Mutant = Data.define(
  :id,             # UUID
  :subject,        # Subject
  :operator,       # "ArithmeticOperator"
  :original_node,  # Parser::AST::Node (original)
  :mutated_node,   # Parser::AST::Node (mutiert)
  :description,    # "replaced + with -"
  :location,       # { file:, start_line:, end_line:, start_col:, end_col: }
  :status,         # :pending | :killed | :survived | :timeout | ...
  :killing_test,   # String | nil
  :duration        # Float | nil (ms)
)
```

#### `PipelineContext`
Trägt den gesamten Pipeline-Zustand durch alle Gates.

```ruby
PipelineContext = Data.define(
  :config,         # Configuration
  :subjects,       # Array<Subject>
  :mutants,        # Array<Mutant>
  :coverage_map,   # Hash<String, Array<String>>  # file → test_files
  :started_at,     # Time
  :git_diff_files  # Array<String> | nil
)
```

---

## 3. Datenfluß durch die Pipeline

```
.henitai.yml ─→ Configuration
git diff output   ─→ GitDiffAnalyzer
                          │
                          ▼
              ┌───────────────────────┐
              │  Gate 1               │
              │  SubjectResolver      │
              │                       │
              │  1. Parse source files│
              │     (parser gem)      │
              │  2. Filter by --since │
              │     (git diff)        │
              │  3. Match patterns    │
              │     (CLI args)        │
              └──────────┬────────────┘
                         │  Array<Subject>
                         ▼
              ┌───────────────────────┐
              │  Gate 2               │
              │  MutantGenerator      │
              │                       │
              │  1. AST traversal per │
              │     Subject           │
              │  2. Apply operators   │
              │     (light | full)    │
              │  3. Filter arid nodes │
              │  4. Filter stillborn  │
              │     (syntax check)    │
              └──────────┬────────────┘
                         │  Array<Mutant> (status: :pending)
                         ▼
              ┌───────────────────────┐
              │  Gate 3               │
              │  StaticFilter         │
              │                       │
              │  1. ignore_patterns   │
              │     (config regex)    │
              │  2. Coverage data     │
              │     (SimpleCov JSON)  │
              │  3. Mark :no_coverage │
              │     + :ignored        │
              └──────────┬────────────┘
                         │  Array<Mutant> (pending/no_coverage/ignored)
                         ▼
              ┌───────────────────────┐
              │  Gate 4               │
              │  ExecutionEngine      │
              │                       │
              │  Per Mutant:          │
              │  1. Fork child        │
              │  2. Inject mutation   │
              │     (define_method)   │
              │  3. Run selected      │
              │     tests (rspec)     │
              │  4. Collect result    │
              │  5. Kill on first     │
              │     failure           │
              └──────────┬────────────┘
                         │  Array<Mutant> (alle final)
                         ▼
              ┌───────────────────────┐
              │  Gate 5               │
              │  ResultCollector      │
              │                       │
              │  1. Build Result      │
              │  2. to_stryker_schema │
              │  3. Run reporters     │
              │  4. Exit code         │
              └───────────────────────┘
```

### Mutant-Injektion (Gate 4 Detail)

Das kritische Implementierungsdetail: Mutationen werden **nicht** als temporäre Dateien geschrieben, und RSpec wird **nicht** als separater Subprocess gestartet (`exec`/`system`). Stattdessen läuft alles im selben geforkten Kindprozess:

```ruby
# Im Elternprozess (ExecutionEngine), vor fork:
Activator.serialize(mutant, tmpfile)   # Mutant-Daten in tmpfile schreiben

pid = Process.fork do
  # ── CHILD ────────────────────────────────────────────────────────────
  # Schritt 1: Mutation aktivieren (vor RSpec)
  Activator.load_and_apply(tmpfile)    # define_method patcht Zielklasse

  # Schritt 2: Tests im GLEICHEN Prozess starten (kein exec!)
  status = RSpec::Core::Runner.run(test_files)
  exit(status)
  # ─────────────────────────────────────────────────────────────────────
end

# Im Elternprozess: auf Kind warten, Timeout erzwingen
result = wait_with_timeout(pid, config.timeout)
```

`define_method`-Patches sind prozesslokal — ein separater RSpec-Subprocess würde die Patch-Information nicht erben. Der Elternprozess wertet den Exit-Code aus: 0 → survived, != 0 → killed, SIGTERM/SIGKILL → timeout.

---

## 4. Implementierungsphasen

### Phase 1 — Fundament (MVP)

**Ziel:** Ein lauffähiges Framework, das für ein einfaches Ruby-Projekt end-to-end funktioniert.

**Definition of Done:**
- `bundle exec henitai run` terminiert erfolgreich
- Mindestens 5 Operatoren (Light Set) implementiert
- JSON-Report (Stryker-Schema) wird korrekt generiert
- CI-Pipeline (GH Actions) ist grün
- Das Framework testet sich selbst (Dogfooding)

**Geschätzter Aufwand:** 8–12 Wochen (Einzelentwickler, Teilzeit)

---

### Phase 2 — Produktionsreife

**Ziel:** Framework ist für mittlere Ruby-Projekte (5.000–20.000 LOC) praktikabel einsetzbar.

**Definition of Done:**
- Alle Light + Full Operatoren implementiert
- Inkrementeller Modus (`--since`) funktioniert zuverlässig
- HTML-Report via `mutation-testing-elements`
- Stryker Dashboard Integration
- Performance: < 10 Min für 10.000 LOC Projekt (mit `--since`)

**Geschätzter Aufwand:** 8–16 Wochen nach Phase 1

---

### Phase 3 — Ökosystem & Intelligenz

**Ziel:** Adoption, Erweiterbarkeit, LLM-Integration.

**Definition of Done:**
- Plugin-API für Custom-Operatoren dokumentiert und stabil
- LLM-Äquivalenz-Detektor als optionales Plugin
- Minitest-Integration
- Latent-Mutant-Tracking

**Geschätzter Aufwand:** unbegrenzt / iterativ

---

## 5. Task-Breakdown

### Legende

| Symbol | Bedeutung |
|--------|-----------|
| `[ ]` | offen |
| `[~]` | Stub vorhanden, Implementierung ausstehend |
| `[x]` | abgeschlossen |
| `[!]` | blockiert / Risiko |
| **(P1)** | Phase 1 |
| **(P2)** | Phase 2 |
| **(P3)** | Phase 3 |

---

### 5.1 Infrastruktur & Gem-Setup

- [x] **(P1)** Gem-Scaffold anlegen (`henitai.gemspec`, `Gemfile`, `.ruby-version`)
- [x] **(P1)** Dev-Container konfigurieren (Ubuntu 24.04, mise, Ruby 4.0.2)
- [x] **(P1)** CI-Pipeline (GitHub Actions: RSpec + RuboCop + inkrementelle MT auf PRs)
- [x] **(P1)** RuboCop-Konfiguration (`TargetRubyVersion: 4.0`, frozen strings)
- [x] **(P1)** SimpleCov-Setup mit Branch-Coverage
- [x] **(P1)** `.henitai.yml` Konfigurations-Schema anlegen
- [ ] **(P1)** `TASK: infra-01` — Abhängigkeiten verifizieren: `parser ~> 3.3`, `unparser ~> 0.6` installierbar unter Ruby 4.0.2
- [ ] **(P1)** `TASK: infra-02` — Steep/RBS Typannotationen: Entscheidung treffen (Scope für Phase 1 begrenzen, nur public API)

---

### 5.2 Konfiguration (`Configuration`)

- [~] **(P1)** `TASK: config-01` — YAML-Parser-Implementierung: `YAML.safe_load_file` mit Symbolisierung, Defaults, Merge-Semantik
- [ ] **(P1)** `TASK: config-02` — CLI-Override: CLI-Flags überschreiben YAML-Werte (letzter gewinnt)
- [ ] **(P1)** `TASK: config-03` — Validierung: Unbekannte Schlüssel warnen, invalide Werte mit sprechendem Fehler abbrechen
- [ ] **(P1)** `TASK: config-04` — Spec: 100 % Coverage für `Configuration` (unit tests ohne FS-Zugriff via tmp-YAML)
- [ ] **(P2)** `TASK: config-05` — Schema-Dokumentation: JSON Schema für `.henitai.yml` generieren (für IDE-Autovervollständigung)

---

### 5.3 Subject-Resolver (Gate 1)

- [ ] **(P1)** `TASK: subject-01` — `SubjectResolver#resolve_from_files(paths)`: Parst Ruby-Dateien mit `parser` gem, extrahiert alle `def`/`def self.` Nodes mit Namespace-Kontext
- [ ] **(P1)** `TASK: subject-02` — Namespace-Auflösung: Korrekte Handhabung von verschachtelten `module`/`class`-Definitionen im AST
- [ ] **(P1)** `TASK: subject-03` — `SubjectResolver#apply_pattern(subjects, pattern)`: Filtert die Subject-Liste nach CLI-Expressions (`Foo#bar`, `Foo*`, etc.)
- [ ] **(P1)** `TASK: subject-04` — `GitDiffAnalyzer#changed_files(from:, to:)`: Shell-Wrapper um `git diff --name-only`, gibt Array<String> zurück
- [ ] **(P1)** `TASK: subject-05` — `GitDiffAnalyzer#changed_methods(from:, to:)`: Mappt Diff-Hunk-Zeilennummern auf Subject-Bereiche
- [ ] **(P1)** `TASK: subject-06` — Spec: Edge Cases — anonyme Klassen, Singleton-Klassen (`class << self`), `attr_accessor`-generierte Methoden, endless methods (`def f = expr`)
- [ ] **(P2)** `TASK: subject-07` — Metaprogramming-Erkennung: `define_method`-Aufrufe als Subject erfassen (Limitation-Dokumentation wenn nicht lösbar)

---

### 5.4 Operator-Basisklasse & Registry

- [~] **(P1)** `TASK: op-01` — `Operator` Basisklasse: `#mutate(node, subject:)`, `self.node_types`, `#build_mutant`, `#node_location` implementieren (Stub → Real)
- [ ] **(P1)** `TASK: op-02` — `Operators` Namespace und Autoload-Einträge in `henitai.rb`
- [ ] **(P1)** `TASK: op-03` — `Operator.for_set(:light)` / `Operator.for_set(:full)`: Gibt instanziierte Operator-Objekte zurück
- [ ] **(P1)** `TASK: op-04` — Arid-Node-Filter: `AridNodeFilter#suppressed?(node, config)` — prüft gegen `ignore_patterns` Regex-Liste und eingebauten Katalog (Logger, Memoization, etc.)
- [ ] **(P1)** `TASK: op-05` — Stillborn-Filter: Nach Mutation `unparser` aufrufen, dann `RubyVM::InstructionSequence.compile` — bei `SyntaxError` Mutant verwerfen

---

### 5.5 Konkrete Operatoren (Light Set — Phase 1)

Jeder Operator braucht: Implementierung + Spec + mindestens 3 dokumentierte Beispiel-Mutationen.

#### ArithmeticOperator
- [ ] **(P1)** `TASK: op-arith-01` — Node-Types: `:send` mit Methoden `+`, `-`, `*`, `/`, `**`, `%`
- [ ] **(P1)** `TASK: op-arith-02` — Mutationsmatrix: `+→-`, `-→+`, `*→/`, `/→*`, `**→*`, `%→*` (symmetrisch, keine Doppelzählung)
- [ ] **(P1)** `TASK: op-arith-03` — Spec: Arithmetik mit Konstanten, mit Methodenaufrufen, mit Klammerung, mit Float-Literalen

#### EqualityOperator
- [ ] **(P1)** `TASK: op-eq-01` — Node-Types: `:send` mit `==`, `!=`, `<`, `>`, `<=`, `>=`, `<=>`, `eql?`, `equal?`
- [ ] **(P1)** `TASK: op-eq-02` — Mutationsmatrix: jeder Operator wird durch jeden anderen ersetzt (volle Matrix, 8×8)
- [ ] **(P1)** `TASK: op-eq-03` — Spec: Vergleiche in Conditionals, in Guard Clauses, in `Comparable`-Implementierungen

#### LogicalOperator
- [ ] **(P1)** `TASK: op-log-01` — Node-Types: `:and`, `:or`, `&&`/`||` als `:send`
- [ ] **(P1)** `TASK: op-log-02` — Mutationen: `&&→||`, `||→&&`, `&&→lhs`, `&&→rhs`, `||→lhs`, `||→rhs`
- [ ] **(P1)** `TASK: op-log-03` — Spec: Short-circuit-Semantik erhalten, `and`/`or` vs `&&`/`||` AST-Unterschied

#### BooleanLiteral
- [ ] **(P1)** `TASK: op-bool-01` — Node-Types: `:true`, `:false`, `:send` (`!expr`)
- [ ] **(P1)** `TASK: op-bool-02` — Mutationen: `true→false`, `false→true`, `!expr→expr`
- [ ] **(P1)** `TASK: op-bool-03` — Spec: Boolean-Literale in Hash-Values, als Default-Arguments, in ternary

#### ConditionalExpression
- [ ] **(P1)** `TASK: op-cond-01` — Node-Types: `:if` (inkl. `unless`), `:case`, `:while`, `:until`
- [ ] **(P1)** `TASK: op-cond-02` — Mutationen: then-Zweig entfernen, else-Zweig entfernen, Bedingung negieren, Bedingung durch `true`/`false` ersetzen
- [ ] **(P1)** `TASK: op-cond-03` — Spec: Modifier-If (`x if cond`), ternary (`cond ? a : b`), `unless`

#### StringLiteral
- [ ] **(P1)** `TASK: op-str-01` — Node-Types: `:str`, `:dstr` (Interpolation)
- [ ] **(P1)** `TASK: op-str-02` — Mutationen: `"foo"→""`, `"foo"→"Henitai was here"`, Interpolation-Ausdruck entfernen
- [ ] **(P1)** `TASK: op-str-03` — Spec: Frozen-String-Literals, heredocs, `%w[]`-Arrays

#### ReturnValue
- [ ] **(P1)** `TASK: op-ret-01` — Node-Types: `:return`, letzter Ausdruck in Methodenbody (impliziter Return)
- [ ] **(P1)** `TASK: op-ret-02` — Mutationen: `return x` → `return nil`, `return x` → `return 0`, `return x` → `return false`, `return true`/`return false` gegenseitig
- [ ] **(P1)** `TASK: op-ret-03` — Spec: Expliziter `return`, impliziter letzter Ausdruck, Guard-Clause `return nil if ...`

---

### 5.6 Konkrete Operatoren (Full Set — Phase 2)

- [ ] **(P2)** `TASK: op-safe-01` — `SafeNavigation`: `&.` → `.` (entfernt Nil-Guard)
- [ ] **(P2)** `TASK: op-range-01` — `RangeLiteral`: `..` ↔ `...` (inclusive ↔ exclusive)
- [ ] **(P2)** `TASK: op-hash-01` — `HashLiteral`: leerer Hash-Ersatz, Symbol-Key-Mutation
- [ ] **(P2)** `TASK: op-pattern-01` — `PatternMatch`: `in`-Arm-Entfernung, Guard-Clause-Mutation
- [ ] **(P2)** `TASK: op-array-01` — `ArrayDeclaration`: `[]` → `[nil]`, Element-Entfernung
- [ ] **(P2)** `TASK: op-block-01` — `BlockStatement`: `{ ... }` → `{}` (leerer Block)
- [ ] **(P2)** `TASK: op-method-01` — `MethodExpression`: Methodenaufruf-Ergebnis durch `nil` ersetzen
- [ ] **(P2)** `TASK: op-assign-01` — `AssignmentExpression`: `+=` ↔ `-=`, `||=` entfernen

---

### 5.7 Mutant-Generator (Gate 2)

- [ ] **(P1)** `TASK: gen-01` — `MutantGenerator#generate(subjects, operators)`: AST-Traversal per Subject, wendet alle aktiven Operatoren auf jeden passenden Node an
- [ ] **(P1)** `TASK: gen-02` — AST-Traversal-Strategie: `Parser::AST::Processor` subklassen (depth-first, pre-order), nur innerhalb des Subject-Zeilenbereichs operieren
- [ ] **(P1)** `TASK: gen-03` — Arid-Node-Integration: Vor Operator-Anwendung prüfen, ob Node suppressed ist
- [ ] **(P1)** `TASK: gen-04` — Stillborn-Filter-Integration: Nach Generierung `SyntaxValidator#valid?(mutant)` aufrufen, invalide verwerfen
- [ ] **(P1)** `TASK: gen-05` — `max_mutants_per_line: 1`-Constraint (Google-Empfehlung): Bei mehreren Mutanten pro Zeile nur den mit höchster Signal-Priorität behalten
- [ ] **(P2)** `TASK: gen-06` — Stratified Sampling: `SamplingStrategy#sample(mutants, ratio:, strategy: :stratified)` — pro Methode `ratio`% samplen, nicht global

---

### 5.8 Statischer Filter (Gate 3)

- [ ] **(P1)** `TASK: filter-01` — `StaticFilter#apply(mutants, config)`: Markiert Mutanten als `:ignored` wenn Location auf `ignore_patterns` matcht
- [ ] **(P1)** `TASK: filter-02` — Coverage-Integration: `SimpleCov`-JSON-Coverage-Report einlesen (`coverage/.resultset.json`), Map `file → [line_numbers]` aufbauen
- [ ] **(P1)** `TASK: filter-03` — No-Coverage-Markierung: Mutanten deren `start_line` nicht in der Coverage-Map auftaucht → Status `:no_coverage`
- [ ] **(P2)** `TASK: filter-04` — Per-Test-Coverage: `SimpleCov::RSpec`-Integration für granulare `test_file → covered_lines`-Map (40–60 % Speedup laut Forschung)

---

### 5.9 Execution Engine (Gate 4)

> **Ausführungsvertrag (wichtig für Korrektheit):** Jeder Mutant läuft in einem **geforkten Kindprozess**. Innerhalb dieses Kindprozesses wird die Mutation via `define_method` eingespielt — *bevor* RSpec Spec-Dateien lädt. Danach wird `RSpec::Core::Runner.run` **im selben Kindprozess** aufgerufen. Es wird kein zweiter `exec`- oder Subprocess gestartet. `define_method`-Patches sind prozesslokal und würden in einem separaten Prozess verloren gehen.
>
> ```
> Elternprozess (Runner)
>   └─ Process.fork ──→ Kindprozess
>         ENV["HENITAI_MUTANT_ID"] = mutant.id
>         Henitai::Mutant::Activator.activate!   # ← patches Klasse via define_method
>         RSpec::Core::Runner.run(test_files)    # ← GLEICHER Prozess, Mutation bereits aktiv
>         exit $?.exitstatus
> ```
>
> **Aktivierungsreihenfolge:** `Activator.activate!` muss vor dem ersten `require` der Ziel-Quelldatei durch RSpec laufen. Da RSpec Quelldateien erst beim Laden der Spec-Dateien per `require_relative` einbindet, reicht es, `activate!` vor `RSpec::Core::Runner.run` aufzurufen — sofern die Quelldatei nicht bereits im Elternprozess geladen und in den Fork-Speicher mitkopiert wurde. In diesem Fall patcht `activate!` die bereits geladene Klasse direkt (was korrekt ist, da `define_method` auch auf bestehenden Klassen funktioniert).

- [ ] **(P1)** `TASK: exec-01` — `ExecutionEngine#run(mutants, integration, config)`: Hauptschleife über alle `:pending`-Mutanten
- [ ] **(P1)** `TASK: exec-02` — Fork-Isolation: `Process.fork` pro Mutant, `HENITAI_MUTANT_ID` ENV-Var setzen, `Process.wait` mit Timeout im Elternprozess
- [ ] **(P1)** `TASK: exec-03` — Mutant-Aktivierung im Child (vor RSpec): `Activator.activate!` lädt Mutant per ID aus dem serialisierten Mutant-Store (tmpfile oder Shared Memory), patcht Zielklasse via `Module#define_method` — **kein exec, kein zweiter Fork**
- [ ] **(P1)** `TASK: exec-04` — Timeout-Handling: `Process.kill(:SIGTERM, pid)` nach `config.timeout` Sekunden im Elternprozess, danach `SIGKILL` nach weiteren 2 Sekunden
- [ ] **(P1)** `TASK: exec-05` — Kill-on-First-Failure: RSpec-Formatter meldet ersten Test-Fehler → Kindprozess ruft `exit(1)` auf (kein `--fail-fast` nötig, da eigener Prozess)
- [ ] **(P1)** `TASK: exec-06` — Exit-Code-Auswertung im Elternprozess: 0 → survived, != 0 → killed, SIGTERM/SIGKILL → timeout
- [ ] **(P1)** `TASK: exec-07` — `Henitai::Mutant::Activator`-Klasse: Serialisiert Mutant-Daten (mutierter AST als String, Klasse, Methode) in tmpfile vor Fork; deserialisiert und patcht im Child
- [ ] **(P2)** `TASK: exec-08` — Parallele Ausführung: Worker-Pool (`Parallel`-Gem oder natives `Ractor`), Anzahl via `config.jobs` oder CPU-Count
- [ ] **(P2)** `TASK: exec-09` — Test-Priorisierung: `TestPrioritizer#sort(tests, mutant, history)` — adaptive Strategie (Tests die bereits andere Mutanten getötet haben, zuerst)
- [ ] **(P2)** `TASK: exec-10` — Flaky-Test-Mitigation: 3× Retry bei survived Mutant, Warnung wenn > 5 % unknown

---

### 5.10 RSpec-Integration

- [ ] **(P1)** `TASK: rspec-01` — `Integration::Rspec#select_tests(subject)`: Longest-Prefix-Matching — scannt `spec/` nach RSpec-Dateien, deren `describe`/`context`-Strings den Subject-Namespace enthalten
- [ ] **(P1)** `TASK: rspec-02` — Fallback: Wenn keine Tests per Prefix gefunden → alle Spec-Dateien die `require` der Source-Datei transitiv enthalten
- [ ] **(P1)** `TASK: rspec-03` — `Integration::Rspec#run_in_child(test_files)`: Ruft `RSpec::Core::Runner.run(test_files + rspec_opts)` im **aktuellen Prozess** auf (wird nach `fork` vom ExecutionEngine-Child aufgerufen — kein separater Subprocess via `exec` oder `system`)
- [ ] **(P1)** `TASK: rspec-04` — Aktivierungsreihenfolge sicherstellen: `exec-03` (`Activator.activate!`) wird von `exec-02` (fork) aufgerufen, **bevor** `rspec-03` (`RSpec::Core::Runner.run`) gestartet wird. Ein Spec-Test verifiziert, dass `define_method`-Patch aktiv ist wenn erster Test läuft.
- [ ] **(P1)** `TASK: rspec-05` — Spec für Integration: Unit-Tests für Prefix-Matching-Logik (kein echter Prozess nötig)
- [ ] **(P2)** `TASK: rspec-06` — Per-Test-Coverage: `--require henitai/coverage_formatter` in RSpec-Optionen, produziert `coverage/henitai_per_test.json`
- [ ] **(P3)** `TASK: minitest-01` — Minitest-Integration analog zur RSpec-Integration

---

### 5.11 Reporter

#### Terminal Reporter
- [ ] **(P1)** `TASK: rep-term-01` — Live-Progress während Gate 4: `·` für killed, `S` für survived, `T` für timeout, `I` für ignored
- [ ] **(P1)** `TASK: rep-term-02` — Summary nach Gate 5: Tabelle mit MS %, Killed/Survived/Timeout/NoCoverage-Counts, Dauer
- [ ] **(P1)** `TASK: rep-term-03` — Survived-Details: Für jeden survived Mutant: Datei, Zeile, Diff (original vs. mutiert), Operator-Name
- [ ] **(P1)** `TASK: rep-term-04` — Threshold-Check: Farbige Ausgabe (grün/gelb/rot) basierend auf `thresholds.high` / `thresholds.low`

#### JSON Reporter (Stryker-Schema)
- [~] **(P1)** `TASK: rep-json-01` — `Result#to_stryker_schema`: Vollständige Implementierung inkl. `files`-Section, `mutants`-Array, korrektes Status-Mapping
- [ ] **(P1)** `TASK: rep-json-02` — Datei-Output: `mutation-report.json` in konfigurierbarem Verzeichnis (`reports/`)
- [ ] **(P1)** `TASK: rep-json-03` — Schema-Validierung in Specs: Gegen JSON Schema v3.5.1 validieren (via `json_schemer` Gem)

#### HTML Reporter
- [ ] **(P2)** `TASK: rep-html-01` — HTML-Template: Einbinden von `mutation-testing-elements` via CDN (`unpkg.com/mutation-testing-elements`)
- [ ] **(P2)** `TASK: rep-html-02` — Self-contained HTML: JSON-Report inline als `<mutation-test-report-app>` Web-Component-Attribut
- [ ] **(P2)** `TASK: rep-html-03` — Output: `reports/mutation-report.html`

#### Dashboard Reporter
- [ ] **(P2)** `TASK: rep-dash-01` — REST-API-Client: `PUT /api/reports/{project}/{version}` mit Bearer-Auth (`STRYKER_DASHBOARD_API_KEY`)
- [ ] **(P2)** `TASK: rep-dash-02` — Projekt-URL aus Config (`dashboard.project`) oder Git-Remote-URL auto-detecten
- [ ] **(P2)** `TASK: rep-dash-03` — CI-Erkennung: `GITHUB_REF`/`GITHUB_SHA` für automatische Version-Bestimmung

---

### 5.12 CLI

- [~] **(P1)** `TASK: cli-01` — `henitai run`: Vollständige Pipeline-Ausführung mit OptionParser
- [ ] **(P1)** `TASK: cli-02` — `henitai run --since GIT_REF`: Inkrementeller Modus, Gate 1 auf geänderte Dateien beschränken
- [ ] **(P1)** `TASK: cli-03` — Exit-Codes: 0 = MS ≥ low-Threshold, 1 = MS < low-Threshold, 2 = Framework-Fehler
- [ ] **(P1)** `TASK: cli-04` — `henitai version`: Gibt `Henitai::VERSION` aus
- [ ] **(P2)** `TASK: cli-05` — `henitai init`: Legt `.henitai.yml` mit sinnvollen Defaults an, fragt interaktiv nach Integration
- [ ] **(P2)** `TASK: cli-06` — `henitai operator list`: Listet alle verfügbaren Operatoren mit Beschreibung und Beispiel-Mutationen

---

### 5.13 Result & Scoring

> **Scoring-Formel (bindend, aus architecture.md Abschnitt 6.1):**
>
> ```
> MS  = detected / (total − ignored − no_coverage − compile_error − equivalent)
> MSI = killed   / total
> ```
>
> `MS` und `MSI` **müssen immer zusammen** ausgegeben werden. Ein Report ohne den Äquivalenz-Vorbehalt ist ein Anti-Pattern (architecture.md Abschnitt 9).
>
> `:equivalent` ist ein Henitai-interner Status — im Stryker-JSON wird er als `"Ignored"` serialisiert (das Stryker-Schema kennt keinen Equivalent-Status). Die Unterscheidung bleibt im `Result`-Objekt für korrekte MS-Berechnung erhalten.

- [~] **(P1)** `TASK: result-01` — `Result#mutation_score`: Korrekte MS-Formel — excl. `:ignored`, `:no_coverage`, `:compile_error`, **`:equivalent`** aus Zähler und Nenner (implementiert in `result.rb`)
- [~] **(P1)** `TASK: result-02` — `Result#mutation_score_indicator`: Naive MSI-Formel — `killed / total`, kein Ausschluss (implementiert in `result.rb`)
- [ ] **(P1)** `TASK: result-03` — Terminal-Report zeigt MS **und** MSI nebeneinander, plus geschätzte Äquivalenz-Unsicherheit (`~10–15 % der lebenden Mutanten`)
- [ ] **(P1)** `TASK: result-04` — Spec: MS/MSI-Berechnung mit Fixture-Mutanten aller Statuses, inkl. `:equivalent` (Regression-Guard gegen Formel-Drift)
- [ ] **(P2)** `TASK: result-05` — Äquivalenz-Heuristiken (MEDIC-Muster): `EquivalenceDetector#analyze(mutant)` markiert Kandidaten mit `:equivalent` — Data-Flow-Pattern (Use-Def, Use-Ret, Def-Def, Def-Ret). Erkennungsrate ~50 % der tatsächlich äquivalenten Mutanten.
- [ ] **(P2)** `TASK: result-06` — Trend-Tracking: `reports/mutation-history.json` — akkumuliert MS/MSI-Werte über Zeit für Trendlinie

---

### 5.14 Dogfooding & Qualitätssicherung

- [ ] **(P1)** `TASK: dog-01` — Henitai testet sich selbst: `bundle exec henitai run --operators light` als Teil der CI-Pipeline (nach Phase 1 abgeschlossen)
- [ ] **(P1)** `TASK: dog-02` — Test-Coverage: ≥ 90 % Statement + Branch via SimpleCov
- [ ] **(P1)** `TASK: dog-03` — RuboCop: 0 Offenses, `TargetRubyVersion: 4.0`
- [ ] **(P2)** `TASK: dog-04` — Mutation Score Ziel: ≥ 70 % (Light Set), ≥ 60 % (Full Set inkl. schwer tötbarer Operatoren)
- [ ] **(P2)** `TASK: dog-05` — Performance-Benchmark: `henitai run` auf dem eigenen Repo in < 3 Minuten

---

## 6. Technische Entscheidungen (ADRs)

### ADR-01: `parser` Gem statt `RubyVM::AbstractSyntaxTree`

**Entscheidung:** AST-Traversal und Code-Rekonstruktion via `parser` + `unparser` Gems.

**Begründung:**
- `RubyVM::AbstractSyntaxTree` hat keine stabile öffentliche API für Code-Generierung
- `parser` ist RuboCop-kompatibel und battle-tested bei großen Ruby-Projekten
- `unparser` ermöglicht zuverlässige AST → Source-Rekonstruktion ohne Whitespace-Verlust
- Source-Locations bleiben erhalten (exakte Zeilen/Spalten für Stryker-JSON nötig)

**Risiko:** `parser` muss Ruby 4.0-Syntax unterstützen. Ggf. Fork oder Wartung nötig.

---

### ADR-02: `Process.fork` statt Threads oder Ractors für Test-Isolation

**Entscheidung:** Jeder Mutant läuft in einem eigenen geforkten Kindprozess.

**Begründung:**
- Vollständige Speicher-Isolation — Mutationen verschmutzen nicht den Elternprozess
- Kompatibel mit allen C-Extensions (Ractor ist nicht C-Extension-kompatibel)
- `Process.fork` + Copy-on-Write profitiert vom geladenen Ruby-Prozess (schneller als fresh start)
- Mutant-Gem-Bewährung: Dieser Ansatz ist in Produktion erprobt

**Einschränkung:** Nicht auf JRuby, TruffleRuby. Dokumentierte Limitation.

---

### ADR-03: Stryker-JSON-Schema als natives Ausgabeformat

**Entscheidung:** `Result#to_stryker_schema` ist die kanonische Serialisierungsform.

**Begründung:**
- Dashboard, HTML-Report und Badges ohne eigene Server-Infrastruktur
- Ruby ist die einzige Sprache ohne Stryker-Implementierung — direkter Anschluss an das Ökosystem
- Zukünftige Stryker-Features (neue Dashboard-Views etc.) werden automatisch unterstützt

**Risiko:** Schema-Versionierung — bei Breaking Changes in Stryker-Schema Anpassung nötig.

---

### ADR-04: `define_method` für Mutant-Injektion (kein Temp-File)

**Entscheidung:** Mutationen werden via `Module#define_method` injiziert, nicht als temporäre Dateien.

**Begründung:**
- Kein Disk-I/O pro Mutant (signifikanter Speedup bei vielen Mutanten)
- Kein Risiko durch gleichzeitige Prozesse die dieselbe Datei schreiben
- Konsistent mit dem Copy-on-Write-Vorteil des Fork-Modells
- Mutant-Gem verwendet denselben Ansatz (Konzept-Übernahme, nicht Code-Übernahme)

**Risiko:** `eval` für Methoden-Body-Rekonstruktion — muss sorgfältig gesandboxed werden.

---

### ADR-05: Stryker-kompatible Operator-Namen

**Entscheidung:** Operatoren werden nach Stryker-Konvention benannt (`ArithmeticOperator`, nicht `AOR`).

**Begründung:**
- Dashboard-Filter und HTML-Report kategorisieren nach diesen Namen
- Konsistenz mit dem Ökosystem vereinfacht Onboarding für Stryker-Nutzer
- Ruby-spezifische Operatoren (`SafeNavigation`, `PatternMatch`) folgen demselben Naming-Pattern

---

## 7. Qualitätskriterien

### 7.1 Definition of Done (pro Task)

Ein Task gilt als abgeschlossen wenn:
1. Implementierung ist vollständig (kein `raise NotImplementedError`)
2. Specs vorhanden und grün (`bundle exec rspec spec/henitai/[component]`)
3. RuboCop: 0 Offenses für die neue/geänderte Datei
4. SimpleCov: Neue Zeilen sind ≥ 90 % covered
5. CHANGELOG.md aktualisiert (unter `[Unreleased]`)

### 7.2 Mindest-Operator-Spezifikation

Jeder Operator muss dokumentieren:
- Welche AST-Node-Types er behandelt
- Vollständige Mutationsmatrix (was wird womit ersetzt)
- Mindestens 3 Beispiele mit Original- und mutiertem Code
- Bekannte False-Positive-Quellen (Arid-Node-Kandidaten)

### 7.3 Performance-Benchmarks (Gate-4-Referenz)

| Projekt-Größe | Ziel (--since, Light Set) | Ziel (Full Run) |
|---|---|---|
| Henitai selbst (~500 LOC) | < 30 Sek | < 3 Min |
| 5.000 LOC | < 3 Min | < 20 Min |
| 20.000 LOC | < 10 Min | < 60 Min |

---

## 8. Risiken & Mitigationen

| # | Risiko | Wahrscheinlichkeit | Auswirkung | Mitigation |
|---|---|---|---|---|
| R1 | `parser` Gem unterstützt Ruby 4.0-Syntax nicht vollständig | Mittel | Hoch | Frühzeitig verifizieren (TASK: infra-01); Fallback: Fork des Gems |
| R2 | `define_method`-Injektion schlägt für bestimmte Methoden fehl (z.B. `initialize`, native methods) | Hoch | Mittel | Whitelist nicht-mutierbarer Methoden; explizite Fehlermeldung statt silent failure |
| R3 | Äquivalente Mutanten erodieren Nutzervertrauen | Mittel | Hoch | Arid-Node-Katalog früh aufbauen; Feedback-Loop in CLI integrieren |
| R4 | Fork-Modell nicht portierbar auf Windows/JRuby | Mittel | Niedrig | Klar dokumentieren; Windows ist Non-Goal für Phase 1 |
| R5 | Stryker-Schema Breaking Change | Niedrig | Mittel | Schema-Version im Output pinnen; Migration-Guide wenn nötig |
| R6 | RSpec-interne APIs für per-test Coverage instabil | Mittel | Niedrig | Per-Test-Coverage ist P2, nicht P1; SimpleCov-Gesamt-Coverage als Fallback |
| R7 | Ruby 4.0.2 nicht stabil genug für Produktion | Niedrig | Hoch | Entwicklung auf RC/stable; `.ruby-version` anpassen wenn nötig |

---

## Anhang: Erste Implementierungsreihenfolge (Phase 1, empfohlen)

Die Abhängigkeiten im Komponentengraph legen diese Reihenfolge nahe:

```
1.  config-01 bis config-04         (Configuration — keine Deps)
2.  op-01 bis op-05                 (Operator Basis — keine Deps)
3.  op-arith bis op-ret (Light Set) (7 Operatoren — nur Operator-Basis)
4.  subject-01 bis subject-06       (SubjectResolver — parser gem)
5.  gen-01 bis gen-05               (MutantGenerator — Operators + Subjects)
6.  filter-01 bis filter-03         (StaticFilter — Configuration)
7.  rspec-01 bis rspec-05           (RSpec-Integration — Integration-Basis)
8.  exec-01 bis exec-06             (ExecutionEngine — Integration + Mutants)
9.  result-01 bis result-03         (Result + Stryker-Schema)
10. rep-term-01 bis rep-term-04     (Terminal Reporter)
11. rep-json-01 bis rep-json-03     (JSON Reporter — Result)
12. cli-01 bis cli-04               (CLI — alles)
13. dog-01 bis dog-03               (Dogfooding — alles)
```

> **Kritischer Pfad:** config → operators → generator → execution → result → cli
> Alle anderen Komponenten können parallel dazu entwickelt werden.
