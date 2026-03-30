# Stryker-Ökosystem-Analyse
## Wiederverwendbarkeit für unser Ruby-Framework

> **Analysierte Quellen:** stryker-mutator.io Docs, GitHub: stryker-js, stryker4s, stryker-net, mutation-testing-elements, stryker-dashboard
> **Stand:** März 2026
> **Kritische Erkenntnis:** Das Stryker-Ökosystem ist bewusst sprachagnostisch designt — ein Ruby-Framework kann Dashboard, HTML-Report und JSON-Schema ohne Änderungen nutzen.

---

## 1. Strategische Einordnung

Stryker ist das breiteste Mutation-Testing-Ökosystem überhaupt: JavaScript/TypeScript (stryker-js), .NET (stryker-net) und Scala (stryker4s) teilen dasselbe JSON-Reporting-Schema, dasselbe Dashboard und dieselben HTML-Visualisierungs-Komponenten. **Ruby ist explizit nicht vertreten** — das ist die Marktlücke.

Die entscheidende Designentscheidung der Stryker-Entwickler: Die gesamte Visualisierungs- und Reporting-Infrastruktur ist in einem sprachagnostischen JSON-Schema verankert. Jedes Werkzeug, das dieses Schema ausgibt, kann sofort Dashboard, Badge und HTML-Report nutzen.

---

## 2. Das mutation-testing-report-schema (kritisch)

### 2.1 Was es ist

Das `mutation-testing-report-schema` (NPM-Paket, aktuelle Version 3.5.1, ~85.000 wöchentliche Downloads) definiert das gemeinsame JSON-Format für alle Stryker-Implementierungen. Es ist der Kern des gesamten Ökosystems.

### 2.2 Vollständige Schema-Struktur

```json
{
  "schemaVersion": "1.7",
  "thresholds": {
    "high": 80,
    "low": 60
  },
  "projectRoot": "/absolute/path/to/project",
  "config": {},
  "files": {
    "relative/path/to/file.rb": {
      "language": "ruby",
      "source": "vollständiger Quellcode als String",
      "mutants": [
        {
          "id": "unique-string-id",
          "mutatorName": "ArithmeticOperator",
          "replacement": "a - b",
          "description": "Replaced + with -",
          "location": {
            "start": { "line": 42, "column": 10 },
            "end":   { "line": 42, "column": 15 }
          },
          "status": "Killed",
          "statusReason": "expected 5 to eq 3",
          "coveredBy": ["test-id-1", "test-id-2"],
          "killedBy": ["test-id-1"],
          "testsCompleted": 2,
          "static": false
        }
      ]
    }
  },
  "testFiles": {
    "spec/my_spec.rb": {
      "source": "...",
      "tests": [
        {
          "id": "test-id-1",
          "name": "MyClass#method returns correct value",
          "location": { "start": { "line": 10, "column": 1 } }
        }
      ]
    }
  }
}
```

### 2.3 Wichtige Schema-Regeln

**Zeilennummern sind 1-basiert** (nicht 0-basiert) — kritisch für korrekte Darstellung im HTML-Report.

**Vollständiger Quellcode ist Pflicht** im `source`-Feld jeder Datei. Das HTML-Report rendert Syntax-Highlighting aus diesem Feld.

**Mutant-Status-Werte** (vollständige Liste):
- `Killed` — Test schlägt fehl durch Mutation (erwünschtes Ergebnis)
- `Survived` — Kein Test schlägt fehl (Test-Lücke)
- `NoCoverage` — Kein Test deckt die mutierte Zeile ab
- `Timeout` — Test läuft zu lange (Mutant vermutlich equivalent)
- `CompileError` — Mutation erzeugt Syntaxfehler (Stillborn)
- `RuntimeError` — Unerwartete Exception während Test-Ausführung
- `Ignored` — Explizit via Konfiguration ignoriert
- `Pending` — Noch nicht analysiert (für inkrementelle Snapshots)

**Thresholds** sind rein visuell — `high` (grün), `low` (orange), darunter (rot) im Dashboard.

### 2.4 Metriken (berechnet aus Mutanten-Status)

```
totalDetected   = Killed + Timeout
totalUndetected = Survived + NoCoverage
totalValid      = totalDetected + totalUndetected
mutationScore   = (totalDetected / totalValid) * 100
```

`CompileError`, `Ignored`, `RuntimeError` gehen nicht in den Score ein.

---

## 3. mutation-testing-elements (HTML-Report)

### 3.1 Was es ist

`mutation-testing-elements` ist eine Sammlung von Web Components (Custom Elements), die das JSON-Schema als Input nehmen und einen vollständigen, interaktiven HTML-Report rendern. Die aktuelle Version rendert:

- Datei-Browser mit Mutation-Score pro Datei
- Inline Diff-Ansicht: Original vs. mutierter Code (Syntax-Highlighted)
- Filtermöglichkeiten nach Status, Operator, Datei
- Theme-Switching (Hell/Dunkel)
- Deep-Links auf einzelne Mutanten
- Metric-Dashboard mit Score-Visualisierung

### 3.2 Integration — zwei Optionen

**Option A: Standalone HTML-Datei (empfohlen für CLI-Tools)**

Das NPM-Paket `mutation-testing-metrics-html-report` erzeugt eine vollständig self-contained HTML-Datei. Kein Server notwendig, öffnet sich direkt im Browser:

```bash
# Installation (einmalig, für den Build-Prozess unseres Gems)
npm install -g mutation-testing-metrics-html-report

# Verwendung
npx mutation-testing-metrics-html-report --input report.json --output report.html
```

Alternativ: Wir bündeln die Web Components direkt ins Gem (Vendor-Ansatz) und generieren HTML selbst via Ruby-ERB-Template mit eingebettetem JSON.

**Option B: Web Component direkt einbetten**

```html
<!DOCTYPE html>
<html>
  <body>
    <mutation-test-report-app></mutation-test-report-app>
    <script src="https://www.unpkg.com/mutation-testing-elements"></script>
    <script>
      document.querySelector('mutation-test-report-app').report = /* JSON hier */;
    </script>
  </body>
</html>
```

### 3.3 Empfehlung für unser Framework

**Vendor-Ansatz:** Die kompilierte JS-Datei von mutation-testing-elements (~500 KB gzipped) in unser Gem einbetten und ein Ruby-Modul schreiben, das die HTML-Datei via ERB-Template generiert. Keine NPM-Dependency für End-User. Das ist der sauberste Ansatz.

---

## 4. Stryker Dashboard

### 4.1 Was es ist

Das Stryker Dashboard (https://dashboard.stryker-mutator.io) ist eine **vollständig Open-Source** Hosting-Plattform für Mutation-Testing-Reports. Es speichert Reports, rendert Badges und zeigt historische Trends.

**Technologie-Stack:** TypeScript/Node.js Backend, Lit Web Components Frontend, Azure Storage für Daten, GitHub OAuth für Auth.

**Self-Hosting:** Möglich, erfordert Azure Storage oder Azurite (lokales Azure-Emulator), PostgreSQL, GitHub OAuth App-Registrierung.

### 4.2 API — vollständige Spezifikation

Unser Framework muss exakt diese API implementieren, um Dashboard-kompatibel zu sein:

```
PUT https://dashboard.stryker-mutator.io/api/reports/{project}/{version}
```

**URL-Parameter:**
- `{project}` = `github.com/{org}/{repo}` (Format ist hart kodiert auf GitHub)
- `{version}` = Branch-Name, Git-Tag oder Git-SHA
- `?module={name}` = optional, für Monorepos

**HTTP-Headers:**
```
Content-Type: application/json
X-Api-Key: {api-key}
```

**Request Body** (zwei Formate):

Minimal (nur Score):
```json
{ "mutationScore": 85.3 }
```

Vollständig (mit vollem Report):
```json
{ ...mutation-testing-report-schema... }
```

**Response:**
- `200 OK` → Report gespeichert, `href`-URL zum Report zurückgegeben
- `401` → Ungültiger API-Key
- `422` → Ungültiges JSON-Format

**API-Key-Generierung:** Via GitHub OAuth auf dashboard.stryker-mutator.io, einmalige Anzeige, dann Hash-gespeichert.

### 4.3 Badge-URL

```
https://badge.stryker-mutator.io/github.com/{org}/{repo}/{branch}
```

Für Monorepo-Module:
```
https://img.shields.io/endpoint?url=https://badge-api.stryker-mutator.io/github.com/{org}/{repo}/{branch}?module={module}
```

### 4.4 Dashboard-Report-URL

```
https://dashboard.stryker-mutator.io/reports/github.com/{org}/{repo}/{branch}
```

### 4.5 Implementierungsplan für "stryker-ruby"

Unser Framework implementiert einen `DashboardReporter`-Plugin, der nach dem Mutations-Lauf automatisch den Report hochlädt:

```ruby
# Konzept (kein mutant-Code):
class DashboardReporter
  DASHBOARD_URL = "https://dashboard.stryker-mutator.io"

  def report(result)
    return unless api_key && project

    payload = ReportSerializer.to_json(result)  # → mutation-testing-report-schema
    upload(payload)
  end

  private

  def project
    ENV["STRYKER_DASHBOARD_PROJECT"] ||
      detect_from_git_remote ||
      config.dashboard.project
  end

  def version
    ENV["GITHUB_REF_NAME"] ||   # GitHub Actions
    ENV["CI_COMMIT_REF_NAME"] || # GitLab CI
    current_git_branch
  end

  def api_key
    ENV["STRYKER_DASHBOARD_API_KEY"] || config.dashboard.api_key
  end
end
```

**Umgebungsvariablen (auto-detect in CI):**
- `GITHUB_REF_NAME` → Branch/Tag (GitHub Actions)
- `CI_COMMIT_REF_NAME` → Branch (GitLab CI)
- `STRYKER_DASHBOARD_API_KEY` → Auth
- `STRYKER_DASHBOARD_PROJECT` → Override für project-Pfad

---

## 5. Stryker-Mutator-Taxonomie

### 5.1 Vollständige Liste StrykerJS-Operatoren (16 Operatoren)

| Operator-Name | Beschreibung | Ruby-Äquivalent |
|---|---|---|
| `ArithmeticOperator` | `+`↔`-`, `*`↔`/`, `%`→`*` | Direkt übertragbar |
| `EqualityOperator` | `>`↔`<`, `>=`↔`>`, `==`↔`!=` | Direkt übertragbar |
| `LogicalOperator` | `&&`↔`\|\|` | `&&`/`\|\|` und `and`/`or` |
| `BooleanLiteral` | `true`↔`false`, `!x`→`x` | Direkt übertragbar |
| `UnaryOperator` | `-val`↔`+val` | Direkt übertragbar |
| `UpdateOperator` | `++`↔`--` | **Nicht in Ruby** (`+=1`/`-=1` stattdessen) |
| `ConditionalExpression` | Ternary-Operator-Mutation | `cond ? a : b` → `true ? a : b` |
| `BlockStatement` | Leert Block-Body | `def f; body; end` → `def f; end` |
| `StringLiteral` | `"hello"` → `""` | Direkt übertragbar |
| `ArrayDeclaration` | `[1,2,3]` → `[]` | Direkt übertragbar |
| `ObjectLiteral` | `{a: 1}` → `{}` | Hash-Literal-Mutation |
| `AssignmentOperator` | `+=`↔`-=`, `*=`↔`/=` | Direkt übertragbar |
| `OptionalChaining` | `obj?.prop` → `obj.prop` | Ruby: `obj&.method` → `obj.method` |
| `MethodExpression` | `filter`↔`find`, `some`↔`every` | Ruby: Methoden-Äquivalente |
| `Regex` | Regex-Pattern-Mutation | Direkt übertragbar |
| `ArrowFunction` | Arrow-Function-Body-Entfernung | Lambda/Proc-Äquivalente |

### 5.2 Stryker.NET-Zusatz-Operatoren (Ruby-relevant)

| Operator | Beschreibung | Ruby-Relevanz |
|---|---|---|
| LINQ Methods | `All()`↔`Any()`, `First()`↔`Last()` | Ruby: `all?`↔`any?`, `first`↔`last` |
| String Methods | `upcase`↔`downcase`, `start_with?`↔`end_with?` | Direkt übertragbar |
| Null-Coalescing | `a ?? b` Mutation | Ruby: `a || b` (→ `LogicalOperator`) |
| Checked Statements | Overflow-Check-Entfernung | Nicht relevant für Ruby |

### 5.3 Ruby-spezifische Ergänzungen (nicht in Stryker)

Diese Operatoren existieren in keiner Stryker-Implementierung, sind aber für Ruby zentral:

| Operator-Name | Beschreibung | Beispiel |
|---|---|---|
| `SafeNavigation` | `&.`-Operator-Mutation | `obj&.method` → `obj.method` |
| `RangeLiteral` | `..`↔`...` (inclusive/exclusive) | `(1..10)` → `(1...10)` |
| `SymbolLiteral` | Symbol durch nil ersetzen | `:name` → `nil` |
| `BlockRemoval` | Block-Argument entfernen | `map { \|x\| x * 2 }` → `map` |
| `HeredocMutation` | Heredoc-Inhalt leeren | `<<~TEXT\nhello\nTEXT` → `""` |
| `PatternMatch` | Pattern-Match-Arm-Mutation | `in { x: Integer }` → `in { x: String }` |
| `MethodMissing` | `method_missing`-Delegation mutieren | Metaprogramming-spezifisch |

### 5.4 Mapping: Stryker → Akademische Taxonomie

| Akademisch | Stryker-Name | Unser Gem-Name (Vorschlag) |
|---|---|---|
| AOR | `ArithmeticOperator` | `ArithmeticOperator` |
| ROR | `EqualityOperator` | `EqualityOperator` |
| LCR | `LogicalOperator` | `LogicalOperator` |
| UOI | `UnaryOperator` | `UnaryOperator` |
| SBR | `BlockStatement` | `BlockStatement` |
| — | `BooleanLiteral` | `BooleanLiteral` |
| — | `StringLiteral` | `StringLiteral` |
| — | `ArrayDeclaration` | `ArrayDeclaration` |
| — | `HashLiteral` | `HashLiteral` *(Ruby-spezifisch)* |
| — | `AssignmentOperator` | `AssignmentOperator` |
| — | `ConditionalExpression` | `ConditionalExpression` |
| — | `RegexLiteral` | `RegexLiteral` |
| — | `SafeNavigation` | `SafeNavigation` *(Ruby-spezifisch)* |
| — | `RangeLiteral` | `RangeLiteral` *(Ruby-spezifisch)* |

**Empfehlung:** Stryker-Operator-Namen 1:1 übernehmen, wo sie existieren. Das macht das JSON-Schema kompatibel mit Stryker-Dashboard-Visualisierungen, die nach `mutatorName` filtern.

---

## 6. Stryker-Architektur-Konzepte für unser Framework

### 6.1 Mutation-Switching (Performance-Gamechanger)

Stryker4s hat die Ausführungszeit von 40 Minuten auf 40 Sekunden reduziert durch **Mutation Switching**: Statt pro Mutant einen neuen Prozess mit geändertem Code zu starten, werden **alle Mutanten gleichzeitig in den Code kompiliert** und via Umgebungsvariable aktiviert.

**Konzept (für Ruby adaptiert):**

```ruby
# Statt: Monkeypatch pro Mutant in getrenntem Fork
# So: Alle Mutanten im Code, Auswahl via ENV

def adult?(age)
  case ENV["ACTIVE_MUTANT"]
  when "mut_001" then age > 18    # Mutation: >= → >
  when "mut_002" then age <= 18   # Mutation: >= → <=
  when "mut_003" then true        # Mutation: Bedingung immer true
  else                age >= 18   # Original
  end
end
```

**Ruby-Umsetzung:** Vor dem Test-Run wird die gesamte Codebase instrumentiert (alle Mutanten eingebettet), einmal geladen, und dann pro Mutant mit gesetztem `STRYKER_ACTIVE_MUTANT`-ENV-Variable ausgeführt. Kein Re-Load pro Mutant.

**Einschränkung:** Dieser Ansatz funktioniert gut für kompilierte Sprachen und ist für Ruby besonders interessant, weil `require` teuer ist. Ein einmaliges Laden der Codebase mit allen Mutanten ist deutlich schneller als N-maliges Laden für N Mutanten.

**Risiko:** Instrumentierter Code ist komplexer, schwerer zu debuggen und kann bei sehr vielen Mutanten Memory-Druck erzeugen. Als optionaler Performance-Modus implementieren (Phase 2).

### 6.2 Dry-Run als Pflicht-Phase

Stryker führt immer einen vollständigen Test-Lauf ohne Mutationen durch, bevor Mutationen beginnen:

1. Stellt sicher, dass die Test-Suite sauber startet (keine vorhandenen Failures)
2. Sammelt per-Test-Coverage-Daten (welcher Test deckt welche Zeile ab)
3. Erkennt **Static Mutants** (Code der nur beim Laden ausgeführt wird)
4. Liefert die Baseline für inkrementelle Snapshots

Wir übernehmen dieses Pattern als Phase 0 unserer Pipeline.

### 6.3 Per-Test-Coverage-Analyse

Stryker nutzt Coverage-Instrumentierung im Dry-Run, um zu bestimmen, welche Tests welche Zeilen abdecken. Bei der Mutation-Phase laufen dann **nur die Tests, die den mutierten Code tatsächlich abdecken**.

Für Ruby: SimpleCov oder Coverage-Modul aus der Standard Library für Instrumentierung nutzen. Das eliminiert redundante Test-Ausführungen.

**Gemessene Effekte (StrykerJS):** 40–60 % schneller als vollständige Test-Ausführung pro Mutant.

### 6.4 Static Mutant Detection

Mutanten in Code, der beim Modul-/Klassen-Laden ausgeführt wird (Konstanten, Class-Level-Code, `after` die Klassen-Definition), sind **Static Mutants**. Sie können nicht per Test-Coverage-Analyse behandelt werden, weil sie vor jedem Test-Run aktiviert sind.

```ruby
# Static Mutant-Beispiel:
class Config
  MAX_RETRIES = 3  # ← Static Mutant: Konstante wird beim Laden gesetzt

  def max_retries
    MAX_RETRIES  # ← Normaler Mutant
  end
end
```

Stryker-Lösung: `ignoreStatic`-Flag um Static Mutants aus dem Score herauszunehmen. Wir implementieren dasselbe.

### 6.5 Worker-Isolation via Umgebungsvariable

Stryker setzt `STRYKER_MUTATOR_WORKER=0`, `=1`, `=2` etc. pro Worker-Prozess. Das ermöglicht:
- Eigene Datenbank pro Worker: `test_db_worker_0`, `test_db_worker_1`
- Eigener Port pro Worker: `4444 + worker_index`
- Eigenes Temp-Verzeichnis pro Worker

Wir übernehmen diese Konvention exakt — damit sind Hook-Dateien aus anderen Stryker-Projekten direkt kompatibel.

### 6.6 Inkrementeller Modus via Snapshot

Stryker speichert einen Snapshot der Ergebnisse (`stryker-incremental.json`) und vergleicht bei erneutem Lauf: Code-Diff + Test-Diff. Mutanten, deren Code und Tests unverändert sind, werden direkt aus dem Snapshot übernommen.

```
stryker-incremental.json: {
  "mutant_id_1": { status: "Killed", killedBy: ["test-1"] },
  "mutant_id_2": { status: "Survived" },
  ...
}
```

**Wiederverwendungsbedingung:** Ein Mutant wird nur wiederverwendet wenn:
- Er `Killed` war UND der tötende Test noch existiert und unverändert ist
- Er `Survived` war UND kein neuer Test ihn abdeckt UND bestehende Tests unverändert sind

---

## 7. Empfehlung: Positioning als "stryker-ruby"

### 7.1 Was das bedeutet

Wir positionieren unser Framework explizit als die Ruby-Implementierung im Stryker-Ökosystem. Das bedeutet:

- JSON-Output ist 100% kompatibel mit `mutation-testing-report-schema`
- Stryker Dashboard wird out-of-the-box unterstützt (kein zusätzliches Setup)
- Stryker-Operator-Namen werden 1:1 übernommen (wo anwendbar)
- Der `STRYKER_MUTATOR_WORKER`-Konvention folgen wir für Worker-Isolation
- Der `STRYKER_DASHBOARD_API_KEY`-Konvention folgen wir für Dashboard-Auth

### 7.2 Was wir nicht von Stryker übernehmen

- Das JavaScript-Plugin-System (typed-inject, DI-Container) — wir nutzen Ruby-idiomatische Plugin-Mechanismen
- Die Dashboard-Infrastruktur selbst (wir nutzen sie nur als Client)
- TypeScript-spezifische Konzepte (Checker für Typfehler)

### 7.3 Vorteil der "stryker-ruby"-Positionierung

Entwickler, die Stryker aus JS- oder .NET-Projekten kennen, haben sofort ein mentales Modell. Das Dashboard-Ökosystem steht vom ersten Tag an bereit. Badges funktionieren sofort. Der GitHub-Survey (Sánchez et al. 2022) zeigt, dass Stryker in der Praxis-Adoption weit vor akademischen Tools liegt.

---

## 8. Offene Fragen

**F1: Vendor vs. NPM für mutation-testing-elements.** Sollen wir die Web-Component-JS-Datei ins Gem einbetten (stable, keine Internet-Abhängigkeit) oder zur Laufzeit von unpkg.com laden (immer aktuell, aber Internet nötig)? Empfehlung: Vendor mit optionalem CDN-Override.

**F2: Dashboard-Kompatibilität für GitLab/selbst-gehostetes GitHub.** Das Dashboard-Projekt-Format ist auf `github.com/{org}/{repo}` festgelegt. GitLab-Projekte wären `gitlab.com/{...}`, aber die Dashboard-API akzeptiert das möglicherweise nicht. Bedarf Verifikation.

**F3: Schema-Version.** Das Schema ist auf Version 3.5.1 (Stand März 2026). Wir sollten Schema-Versioning in unserem JSON-Output explizit managen und bei Schema-Updates automatisch eine neue Version ausgeben.

---

## 9. Zusammenfassung: Was wir direkt wiederverwenden

| Komponente | Wiederverwendung | Aufwand |
|---|---|---|
| `mutation-testing-report-schema` JSON | Vollständig — 1:1 kompatibel | Gering (Schema implementieren) |
| `mutation-testing-elements` HTML-Report | Vollständig — JS-Datei vendoren | Gering (ERB-Template schreiben) |
| Stryker Dashboard API | Vollständig — als Client | Gering (HTTP PUT implementieren) |
| Stryker-Operator-Namen | Übernehmen wo anwendbar | Keine (Benennung nur) |
| `STRYKER_MUTATOR_WORKER` Konvention | Übernehmen | Keine (ENV-Variable lesen) |
| Dashboard Badge-URL | Sofort verfügbar | Keine |
| Dry-Run-Konzept | Übernehmen als Pipeline-Phase | Mittel |
| Per-Test-Coverage-Analyse | Übernehmen (SimpleCov) | Mittel |
| Incremental Snapshot | Übernehmen (JSON-Datei) | Mittel |
| Mutation-Switching | Optionaler Performance-Modus | Hoch (Phase 2) |

---

*Referenzdokument Stryker-Mutator-Taxonomie (vollständig): `STRYKER_MUTATORS_COMPLETE_REFERENCE.md`*
