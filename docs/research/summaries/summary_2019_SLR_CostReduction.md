# A Systematic Literature Review of Techniques and Metrics to Reduce the Cost of Mutation Testing

## 1. Metadaten
- **Titel:** A Systematic Literature Review of Techniques and Metrics to Reduce the Cost of Mutation Testing
- **Autoren:** Alessandro Viola Pizzoleto, Fabiano Cutigi Ferrari, Jeff Offutt, Leo Fernandes, Márcio Ribeiro
- **Jahr:** 2019
- **Venue:** Journal of Systems and Software
- **Paper-Typ:** Systematic Literature Review (SLR)
- **Sprachen/Plattformen im Fokus:** Language-agnostisch; fokussiert auf Cost-Reduction Techniken

## 2. Kernaussage
Umfassende SLR über 153 Primärstudien (1989-2018) zu Kostensenkungstechniken für Mutation Testing. Kategorisiert 6 Primärziele und 21 Techniken; charakterisiert 18 Metriken zur Messung von Cost Reduction; identifiziert Trends zu interdisziplinären und kombinierten Ansätzen.

## 3. Einordnung
- **Vorarbeiten:** Erweitert Offutt & Untch (2000) klassische "do fewer, do smarter, do faster"-Kategorisierung
- **Kritisierte/erweiterte Ansätze:** Modernere Taxonomie (6 Primärziele statt 3); Interdisziplinäre Kombinationen; Metriken-Standardisierung
- **Relevanz für Framework-Design:** hoch — Umfassende Überblick über Cost-Reduction Strategien, Best Practices, Metriken; praktische Implementierungsorientierung

## 4. Technische Inhalte

### Mutationsoperatoren
- **Nicht primärer Fokus;** aber erwähnt Selective Mutation zur Reduktion der Operatorsets
- **Basis-Referenz:** Competent Programmer Hypothesis, Coupling Effect

### Architektur & Implementierung
- **Vier klassische Schritte:**
  1. Execution of original program
  2. Generation of mutants
  3. Execution of mutants (kostspielig)
  4. Analysis of mutants (kostspielig, oft manuell)
- **Mutation Score:** MS = K / (M - E), wobei K = killed, M = total, E = equivalent

### Kostensenkung & Performance
**Offutt & Untch (2000) klassische Kategorisierung:**
- **Do Fewer:** 113 Studien — reduzieren Mutanten-Anzahl ohne Effektivitätsverlust
- **Do Smarter:** 25 Studien (primär), 50 sekundär — Verteilung, State-Retention, partielle Ausführung
- **Do Faster:** 15 Studien — schnellere Generierung und Ausführung

**Moderne 6 Primärziele (dieses Paper):**
1. **PG-1 (5):** Reducing the number of mutants (62 Studien)
   - Mutation Sampling, Clustering, Selective Mutation
2. **PG-2 (≡):** Automatically detecting equivalent mutants (23 Studien)
   - Compiler-Optimierung, Constraint-Analyse, Heuristische Methoden
3. **PG-3 (..):** Executing faster (31 Studien)
   - Weak Mutation, Mutant Schemata, Partial Execution, Hardware-Acceleration
4. **PG-4 (ε):** Reducing number of test cases or executions (17 Studien)
   - Test Suite Reduction, Test Clustering, Mutant Grouping
5. **PG-5 (ψ):** Avoiding creation of certain mutants (11 Studien)
   - Smart Mutant Generation, Non-Trivial Filtering, Operator Constraints
6. **PG-6 (τ):** Automatically generating test cases (16 Studien)
   - Search-Based, Constraint-Based, Symbolic Execution, Concolic Testing

**Zielbeziehungen:** PG-1 impliziert indirekt PG-4 und PG-6

### Equivalent-Mutant-Problem
- **Undecidable Problem:** Budd & Angluin (1977)
- **Strategien:** Detecting, Avoiding, Suggesting
- **Praktisch:** Oft manuelle Analyse erforderlich; Äquivalenz-Erkennung eine der Hauptbarrieren

### Skalierbarkeit & Integration
- **Trend (2008-2018):** Exponentielles Wachstum der Cost-Reduction-Forschung
- **Kombination:** Viele moderne Studien kombinieren mehrere Techniken (z.B. Control-Flow + Metamutants)
- **Effektivitätsmessungen:** Variieren erheblich auch bei identischen Techniken
- **Publikations-Orte:** IEEE (37,9%), ACM (21,6%), Springer (9,8%), Elsevier (11,1%), Wiley (13,1%)

## 5. Empirische Befunde
- **Stichprobe:** 175 Papiere ausgewertet, 153 nach Subsumtion (Deduplication)
- **Zeitraum:** 1989-2018 (Fokus 2009-2018)
- **Publikationstrend:** Kontinuierlich steigend; 18+ Papiere/Jahr ab 2013
- **Kategorie-Verteilung (Offutt & Untch):**
  - 1st Category: Do Fewer (113), Do Smarter (25), Do Faster (15)
  - 2nd Category: Do Fewer (5), Do Smarter (50), Do Faster (6) — Kombinationen
- **Fokus 2013:** 17 von 18 Papieren „Do Fewer"; 11 von 18 „Do Smarter"
- **Probleme der Evaluation:** Messungen variieren zwischen Studien; Metriken nicht standardisiert

## 6. Design-Implikationen für mein Framework
- **Modulare Cost-Reduction:** Framework sollte alle 6 Primärziele adressieren können
- **PG-1 als Basis:** Mutation Sampling/Clustering/Selective Mutation als Default-Optionen
- **PG-3 implementieren:** Weak Mutation als Optional; Mutant Schemata für Performance
- **PG-2 Unterstützung:** Heuristische Equivalent-Detektion (Compiler-Optimierung, Coverage-Analysis)
- **PG-5 im Design:** Smart Mutant Generation mit Constraints zur Vermeidung trivialer/äquivalenter Mutanten
- **PG-6 Optional:** Integrierbare Test-Generation (Search-Based, Constraint-Based)
- **Komposierbarkeit:** Framework sollte Kombinationen von Techniken ermöglichen (z.B. PG-1 + PG-3)
- **Metriken-Tracking:** Standardisierte Messung von Savings und Effectiveness (Mutation Score)
- **Konfigurierbarkeit:** Benutzer sollte zwischen Do Fewer, Do Smarter, Do Faster auswählen können

## 7. Offene Fragen & Limitationen
- **Limitationen:**
  - Paper endet August 2018; schnelle Entwicklung des Felds
  - Messungen und Metriken noch nicht standardisiert
  - Große Variation in Effektivitätsgewinnen zwischen Studien
- **Offene Fragen:**
  - Welche Kombination von Techniken ist optimal für verschiedene Szenarien?
  - Wie können Metriken standardisiert werden für bessere Vergleichbarkeit?
  - Welche Cost-Reduction-Strategien sind für große industrielle Systeme am praktischsten?
  - Wie korrelieren Cost-Reduction-Techniken mit echter Fault-Detection?
  - Welche Techniken funktionieren am besten für verschiedene Programmiersprachen?
