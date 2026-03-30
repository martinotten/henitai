# Goal-Oriented Mutation Testing with Focal Methods

## 1. Metadaten
- **Titel:** Goal-Oriented Mutation Testing with Focal Methods
- **Autoren:** Sten Vercammen (Universität Antwerpen), Mohammad Ghafari (Universität Bern), Serge Demeyer (Universität Antwerpen), Markus Borg (RISE SICS)
- **Jahr:** 2018
- **Venue:** ACM Conference (arXiv)
- **Paper-Typ:** Tool-Paper, Machbarkeitsstudie
- **Sprachen/Plattformen im Fokus:** Java

## 2. Kernaussage
Das Paper schlägt Goal-Oriented Mutation Testing vor: durch Identifikation von Focal Methods (Kern-Testmethoden) mittels feingranularer Traceability können nur Test-Cases ausgeführt werden, die tatsächlich die betreffende Methode testen. Dies reduziert Mutation-Testing-Zeit drastisch (573,5x Speedup bei Focal Methods) und ermöglicht präzisere Qualitätsbewertung auf Method-Level statt File/Suite-Level.

## 3. Einordnung
- **Vorarbeiten:** Nutzt Focal-Methods-Konzept aus Ghafari et al. (2015, 2017) zur API-Beispiel-Extraktion; kombiniert mit Spektrums-basierter Fault Localization (DDU-Metrik)
- **Kritisierte/erweiterte Ansätze:** Bisherige Optimierungen (Test Prioritization, Regression Test Selection, Symbolic Execution) fokussieren auf Gesamttests; Goal-Oriented fokussiert auf Methoden-Qualität
- **Relevanz für Framework-Design:** Mittel-Hoch — innovative Perspektive auf Mutation Testing als Qualitätsbewertung per Method, nicht global

## 4. Technische Inhalte

### Mutationsoperatoren
Nicht primär; nutzt LittleDarwin Mutation Framework für Java.

### Architektur & Implementierung
- **Ebene:** AST/Bytecode (LittleDarwin)
- **Konzept - Focal Methods:** Unit-Test-Struktur in 3 Teile: Setup (Vorbereitung), Execution (Aufruf focal method), Oracle (Assertion). Focal Method = letzte Methode, die Objekt-State ändert

**Beispiel:**
```java
testWithdraw():
  Setup: account.createAccount(), account.authenticate()
  Execution: withdraw(6)  // <- Focal Method
  Oracle: assertTrue(success), assertEqual(balance, 4)
```

- **Pruning:** Für Mutant in Methode f: nur Tests ausführen, für die f ein Focal Method ist
- **Quality Score:** % Mutanten in f, die von fokalen Tests getötet werden (Verantwortung der spezialisierten Tests)

### Kostensenkung & Performance
**Speedup-Mechanismus:**
- Full Test Suite: 1.777 Tests (für Apache Ant)
- Class-Based: ~15 Tests durchschnittlich
- Focal Method-Based: ~8,6 Tests durchschnittlich
- **Resultierende Speedups:** 251,5x (Class-Based) zu 573,5x (Focal Methods)

**Trade-off:**
- Full Suite detektiert 44/55 (100%) Mutanten
- Class-Based: 36/55 (82%)
- Focal Methods: 35/55 (80%) — aber 20% False Negatives sind durch Test-Qualität erklärbar

### Equivalent-Mutant-Problem
Nicht primär adressiert; Fokus auf Reduction, nicht Äquivalenz-Erkennung.

### Skalierbarkeit & Integration
- **Evaluierung:** Apache Ant (14.204 Commits, 98 Beiträger, 229K LOC, 1.777 Test-Cases, 16.354 Mutanten)
- **Manuelle Analyse:** 423 Mutanten untersucht (zu Ihnen wurde manuell Focal-Method-Status bestimmt; Tool existiert aber)
- **Limitierung:** Nur 55/423 (13%) Mutanten in Focal Methods identifiziert (Rest in nicht-direkt getesteten Methoden)
- **Größtes Problem:** Private Methods werden meist indirekt getestet (über Public Methods); aktuelle Focal-Method-Definition erkennt diese nicht

## 5. Empirische Befunde
- **Testsubjekte/Benchmarks:** Apache Ant (4 Klassen näher untersucht: AntClassLoader, AntDefaultLogger, DirectoryScanner, IntrospectionHelper)
- **Methodik:** Manuelle Identification fokaler Methoden in Test-Cases; Vergleich Full Suite vs. Class-Based vs. Focal Methods; LittleDarwin für Mutation
- **Zentrale Ergebnisse:**
  - **RQ1:** Focal Methods findbar, aber nur für 13% Mutanten (Grund: indirekt getestete Private Methods)
  - **RQ2 - Speedup:** 573,5x für Mutanten in focal methods; 1.010,1x für einzelne Best-Case-Klasse (AntClassLoaderTest)
  - **Quality Score:** 80% durchschnittlich (35 von 44 erkannte Mutanten via Focal Methods)
  - **False Negatives:** 9 Mutanten nicht erkannt, aber diese sind in Tests mit Eager Test Code Smell (Eager Tests testen mehrere Methoden gleichzeitig)
  - **Precision bei großen Test-Suites:** Je größer die Klassen-Test-Suite, desto größer der relative Speedup
- **Beobachtung:** Focal Methods nutzen Vorteile nur für einzelne Methods mit umfangreichen Test-Suites

## 6. Design-Implikationen für mein Framework
- **Granularität:** Framework sollte Method-Level-Bewertung unterstützen, nicht nur File/Suite-Level
- **Focal Method Detection:** Tool zur automatischen Focal-Method-Identifikation integrieren oder as Hook anbieten (auf basierend Ghafari et al. Tool)
- **Indirect Testing:** Extension der Focal-Method-Definition für indirekte Private-Method-Tests (zukünftige Verbesserung erkannt)
- **Test-Filtering:** Für jeden Mutanten: nur relevante Test-Cases ausführen (Traceability Link)
- **Quality Metrics:** Per-Method Quality Scores berechnen und berichten (nicht nur Global Mutation Score)
- **Test Smells Detection:** Integration von Eager-Test-Code-Smell-Detection; Framework sollte warnen, wenn Tests zu viele Methoden gleichzeitig testen
- **Konfigurierbarkeit:** Fallback zu Class-Based oder Suite-Based, wenn Focal Methods nicht ausreichend Abdeckung bieten

## 7. Offene Fragen & Limitationen
- **Recall Rate:** Nur 13% der Mutanten in Focal Methods gefunden; größte praktische Limitierung
- **Private Methods:** Hauptproblem ist indirekte Testung privater Methoden; benötigt Extension der Definition
- **RIPR-Modell Verletzung:** Focal Methods können Tests ausschließen, die RIPR-Bedingungen erfüllen würden (Reachability, Infection, Propagation, Revealability)
- **Manual Identification:** In dieser Studie manuelle Identification; Tool könnte Fehler einführen
- **Generalisierung:** Nur 423 Mutanten auf großem Projekt evaluiert; Generalisierbarkeit unklar
- **Integration Tests:** Approach funktioniert nur für Unit Tests; nicht für Integration/System Tests
- **Code Smells Impact:** Test Suites mit vielen Code Smells (Eager Tests, etc.) bekommen weniger Benefit
- **Tool Reliability:** Externes Tool (LittleDarwin) könnte Inaccuracies einführen; Paper nutzt manuelle Analyse

## 8. Zusätzliche Insights
- **Motivation:** Basiert auf Spectrum-Based Fault Localization (DDU-Metrik) — Diversität und Einzigartigkeit von Tests verbessert Diagnosability
- **Test Quality vs. Suite Quality:** Philosophischer Paradigma-Shift: Qualität einzelner Tests vs. Gesamt-Suite-Qualität
- **Eager Test Code Smell:** Identifiziert test code smell als praktisches Hindernis für diese Technik
