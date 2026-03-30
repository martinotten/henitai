# Faster Mutation Testing Inspired by Test Prioritization and Reduction

## 1. Metadaten
- **Titel:** Faster Mutation Testing Inspired by Test Prioritization and Reduction
- **Autoren:** Lingming Zhang, Darko Marinov, Sarfraz Khurshid
- **Jahr:** 2013
- **Venue:** ISSTA (International Symposium on Software Testing and Analysis)
- **Paper-Typ:** Empirische Studie
- **Sprachen/Plattformen im Fokus:** Java

## 2. Kernaussage
Das Paper präsentiert FaMT (Faster Mutation Testing), eine Familie von Techniken zur Kostensenkung im Mutation Testing durch Test-Priorisierung und Test-Reduktion. Im Gegensatz zu früheren Ansätzen adressiert FaMT beide Hauptkostenfaktoren: Reduktion von Tests bei tötbaren Mutanten (Priorisierung) und Reduktion von Tests bei nicht tötbaren Mutanten (Reduktion).

## 3. Einordnung
- **Vorarbeiten:** Bezieht sich auf Regression Test Prioritization (Rothermel et al., Do et al.), Regression Test Reduction (Harrold et al., Chen & Lau), selective mutation testing (Mathur, Namin et al.), weak mutation testing (Howden), und das frühere ReMT-Tool der Autoren (für evolvierende Code)
- **Kritisierte/erweiterte Ansätze:** Kritisiert, dass ReMT nur für sich ändernde Programme funktioniert und alte Ergebnisse benötigt; zeigt, dass Regressions-Test-Priorisierung nicht direkt auf Mutation Testing übertragbar ist
- **Relevanz für Framework-Design:** hoch — Priorisierungs- und Reduktionsstrategien sind zentral für praktische Skalierbarkeit

## 4. Technische Inhalte

### Mutationsoperatoren
Nicht spezifisch adressiert; Paper konzentriert sich auf Test-Verwaltung, nicht auf Operator-Definition.

### Architektur & Implementierung
- **Tool:** Implementiert auf Basis von Javalanche (State-of-the-Art Mutation Testing Tool für Java)
- **Ebene:** Source-Code-Mutation
- **Algorithmen:**
  - **Coverage-Based Initial Test Ordering:** Drei Heuriken basierend auf Test-Coverage:
    - C1: Häufigkeit, mit der Test die mutierte Statement ausführt
    - C2: Verhältnis der Statements vor/nach der mutierten Statement
    - C3: Kombination von C1 und C2
  - **Power-Based Adaptive Test Ordering:** Berechnet "Power" eines Tests (Wahrscheinlichkeit, Mutant zu töten) basierend auf Execution History bei anderen Mutanten
    - P1: Power basierend auf allen Nachbar-Mutanten
    - P2: Power nur basierend auf bereits getöteten Nachbar-Mutanten
  - **Neighborhood Levels:** Statement-level, Method-level, Class-level, Global-level History

### Kostensenkung & Performance
- **Priorisierung (FaMT Prioritization):**
  - Präzise: liefert exakte Mutation Score
  - Reduktion: bis zu 47,52% weniger Test-Executions für getötete Mutanten
  - Mittlere Reduktion über alle 9 Projekte: 17–38% je nach Konfiguration
- **Reduktion (FaMT Reduction):**
  - Approximativ: kann Mutation Score underschätzen
  - Reduktion: ~50% aller Test-Executions mit nur ~0,50% Fehlerrate (Statement-Level + P1)
  - Alternative: >63% Reduktion mit <1,22% Fehlerrate (Global-Level + P2)
- **Runtime Overhead:** Maximal 18,34s (auf Jaxen Project mit 2901s Basis-Zeit) — vernachlässigbar

### Equivalent-Mutant-Problem
Nicht thematisiert.

### Skalierbarkeit & Integration
- **Testsubjekte:** 9 Java-Projekte (2,6 KLOC bis 36,9 KLOC), 55–3818 Tests, 1173–36418 Mutanten
- **Orthogonale Techniken:** Kompatibel mit anderen Optimierungsansätzen (Schwach-Mutation, Schema-basierte Mutation, Parallelisierung)
- **Konfigurierbarkeit:** 352 Priorisierungs-Varianten, 3872 Reduktions-Varianten untersucht

## 5. Empirische Befunde
- **Testsubjekte/Benchmarks:** 9 Open-Source Java-Projekte: Time&Money, Jaxen, Xml-Sec, Com-Lang, JDepend, Joda-Time, JMeter, Mime4J, Barbecue
- **Methodik:**
  - 20 Runs pro Konfiguration (aufgrund randomisierter Mutant-Execution-Order)
  - Systematische Variation von: Initial Ordering (4), Test Power Formula (2), History Level (4), Threshold (11), MinRatio (11)
  - Vergleich mit Random Techniques und Regression Testing Techniques
- **Zentrale Ergebnisse:**
  - FaMT Prioritization effektiv (17–38% Reduktion), Regression Prioritization nicht geeignet (-144% bis 67,4%)
  - FaMT Reduction erreicht 50–63% Reduktion mit stabilen, niedrigen Fehlerquoten
  - Global-Level History + P2 Formula: beste Reduktion (63,3%) mit niedriger Fehlerrate (1,14%)
  - Statement-Level History + P1 Formula: stabile Fehlerquote (0,05–0,77%) trotz geringerer Reduktion (50%)
  - MinRatio von 0,1–0,5 und Threshold von 0,1–0,5 sind kostenoptimal

## 6. Design-Implikationen für mein Framework
1. **Zweistufiges Reduktionsmodell implementieren:** Separate Strategien für tötbare und nicht-tötbare Mutanten
2. **History-gestützte Heuristiken:** Adaptive Priorisierung basierend auf Execution-History ist sehr effektiv
3. **Konfigurierbare Granularität:** Framework sollte mehrere Neighbourhood-Level unterstützen (Statement, Method, Class, Global)
4. **Coverage-Information sammeln:** Vorberechnete Coverage-Metriken (C1, C2, C3) sind erforderlich
5. **Approximative Reduktion kalibrierbar machen:** MinRatio und Threshold sollten justierbar sein für Trade-off zwischen Reduktion und Genauigkeit
6. **Tool-Integration:** Integrierbar mit anderen Optimierungen, nicht konkurrierend

## 7. Offene Fragen & Limitationen
- **Limitationen:**
  - Nur Java-Programme getestet
  - Ergebnisse möglicherweise nicht auf andere Test-Suites übertragbar
  - Basiert auf Javalanche-generierten Mutanten — Generalisierbarkeit auf andere Mutation-Tools unklar
  - Keine Analyse, wie FaMT mit Higher-Order Mutants interagiert
  - Abhängigkeit von Reachability-Analyse nicht vollständig untersucht
- **Offene Fragen:**
  - Wie verhalten sich die Techniken bei sehr großen Mutation Sets (>100K Mutanten)?
  - Sind die optimalen Threshold/MinRatio-Werte domain-spezifisch?
  - Wie funktioniert FaMT bei Test-Suites mit stark variierenden Test-Kosten?
  - Kann Man-Power-Formeln für neue Programmiersprachen/Paradigmen adaptieren?
