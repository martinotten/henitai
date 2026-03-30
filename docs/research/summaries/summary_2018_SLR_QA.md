# A Systematic Literature Review of How Mutation Testing Supports Quality Assurance Processes

## 1. Metadaten
- **Titel:** A Systematic Literature Review of How Mutation Testing Supports Quality Assurance Processes
- **Autoren:** Qianqian Zhu, Annibale Panichella, Andy Zaidman (Delft University of Technology)
- **Jahr:** 2018
- **Venue:** Software Testing, Verification and Reliability (STVR)
- **Paper-Typ:** Systematic Literature Review (SLR)
- **Sprachen/Plattformen im Fokus:** Fortran, C, Java, SQL und weitere; Focus auf praktische Anwendungen

## 2. Kernaussage
Systematische Literaturübersicht über 191 Papiere (1981-2015) zur praktischen Anwendung von Mutation Testing in QA-Prozessen. Identifiziert Anwendungsdomänen, Werkzeuge, Operatoren und Kostensenkungsstrategien in realen Szenarien; dokumentiert Lücken zwischen Theorie und Praxis.

## 3. Einordnung
- **Vorarbeiten:** Erweitert DeMillo (1989), Offutt & Untch (2000), Jia & Harman (2010), Madeyski et al. (2014)
- **Kritisierte/erweiterte Ansätze:** Applikations-Fokus statt Theorie-Fokus; systematisches Vorgehen (SLR-Methodik)
- **Relevanz für Framework-Design:** hoch — Praktische Anwendungsmuster, Werkzeugunterstützung, Reporting Best Practices

## 4. Technische Inhalte

### Mutationsoperatoren
- **Basis-Set:** ABS, AOR, ROR, LCR, UOI (Offutt et al. Standard)
- **Häufig angewendet:** Aber viele Studien verwenden unvollständige oder nicht-standardisierte Operatorsets
- **Problem:** Viele Papiere spezifizieren verwendete Operatoren nicht ausreichend
- **Kategorisierung:** Language-spezifische Operatoren für verschiedene Sprachen

### Architektur & Implementierung
- **Mutation-Tools (historisch bis 2015):**
  - Mothra (Fortran, 1977)
  - Proteum (C)
  - Mujava (Java)
  - SQLMutation (SQL)
- **Prozess-Komponenten:**
  - Mutant Creation Engine
  - Equivalent Mutant Detector
  - Test Execution Runner
- **Language-System Ansatz:** Programme müssen geparst, modifiziert und ausgeführt werden

### Kostensenkung & Performance
- **Drei Klassische Strategien (Offutt & Untch):**
  - Do Fewer: Mutant-Sampling, Clustering, Selective Mutation
  - Do Smarter: (nicht explizit detailliert)
  - Do Faster: (nicht explizit detailliert)
- **Zwei-Klassen-Ansatz (Jia & Harman):**
  - Reduktion der generierten Mutanten (Sampling, Clustering, Selective)
  - Reduktion der Ausführungskosten (Weak Mutation, Mutant Schemata)
- **Empirische Befunde:** Selective Mutation, Sampling und Clustering sind am weitesten verbreitet

### Equivalent-Mutant-Problem
- **Undecidable Problem:** Budd & Angluin (1977) bewies Nicht-Entscheidbarkeit
- **Drei Ansatz-Kategorien (Madeyski et al. 2014):**
  1. **Detecting:** Compiler-Optimierung, Program Slicing, Change-Impact-Analyse, Running Profile, Model Checking
  2. **Avoiding:** Selective Mutation, Program Dependence Analysis, Co-Evolutionary Search
  3. **Suggesting:** Bayesian Learning, Dynamic Invariants, Coverage-Change-Analyse
- **Praktisches Problem:** Menschliche Untersuchung sehr zeitaufwändig

### Skalierbarkeit & Integration
- **Test-Levels:** Unit-Test dominiert; Integration und Spezifikations-Level unterrepräsentiert
- **Quality Assurance Prozesse (identifizierte Anwendungen):**
  - Test Data Generation (Constraint-Based Testing, Dynamic Symbolic Execution, Concolic Testing, Search-Based)
  - Test Strategy Evaluation (Structural Coverage vs. Fault-Finding)
  - Test Case Prioritisation (Mutation Score basiert)
  - Test Suite Reduction (Ping-Pong Heuristics)
  - Fault Localisation (Debugging Support)
- **Hauptanwendung:** Assessment von Test-Suites (typische Verwendung)

## 5. Empirische Befunde
- **Stichprobe:** 191 Papiere mit ausreichenden Anwendungsdetails
- **Zeitraum:** 1981-2015
- **Klassifizierung der Studien:**
  - Test Data Generation
  - Test Strategy Assessment
  - Test Case Prioritisation
  - Test Suite Reduction
  - Fault Localisation
- **RQ1 Ergebnisse:** Mutation meist als Assessment-Tool für Unit-Tests; viele Unterstützungstechniken noch underdeveloped
- **RQ2 Ergebnisse:** Reporting-Standards für Mutation Tools, Operatoren, Equivalence, Cost-Reduction Techniken oft unvollständig
- **Vergleich mit Realen Faults:** Andrews et al. zeigte mit sorgfältig ausgewählten Operatoren und Equivalent-Removal gute Korrelation

## 6. Design-Implikationen für mein Framework
- **Anwendungs-Fokus:** Framework sollte primär Assessment unterstützen; daneben Test Data Generation und Case Prioritisation
- **Tool-Design:** Explizite Spezifikation von Mutation Tools, Operatoren, Equivalence-Handling und Cost-Reduction in der API
- **Reporting & Dokumentation:** Framework sollte automatisch Best-Practice-Reports generieren (welche Operatoren, welche Tools, welche Reduction Techniken)
- **Unit-Test Focus:** Primäre Zielgruppe sind Unit-Level Tests; Extensibility für Integration/Specification Level
- **Cost-Reduction als Default:** Selective Mutation, Sampling oder Clustering sollte konfigurierbar sein
- **Operator-Taxonomie:** Standardisierte Operatorsets pro Sprache; Dokumentation aller unterstützten Operatoren
- **Equivalent-Handling:** Heuristische Methoden einbauen; Benutzer warnen bei potentiellen Equivalent Mutanten
- **Replicability:** Framework sollte alle notwendigen Parameter für Replicability dokumentieren

## 7. Offene Fragen & Limitationen
- **Limitationen:** Paper endet 2015; basiert auf Reporting-Praxis bis dahin
- **Offene Fragen:**
  - Wie verbessert sich Reporting zwischen 2015 und 2018?
  - Welche Cost-Reduction Strategie ist für welche Szenarien optimal?
  - Wie können Operator-Sets automatisch für spezifische Domänen optimiert werden?
  - Wie gut korreliert Mutation mit echten Faults in modernen Systemen?
  - Wie skaliert Mutation Testing auf große industrielle Systeme?
- **Hauptbefund:** Große Lücke zwischen Theorie (380+ Papiere) und praktischer Anwendung (191 mit ausreichendem Detail)
