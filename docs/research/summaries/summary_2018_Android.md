# Reducing the Cost of Android Mutation Testing

## 1. Metadaten
- **Titel:** Reducing the Cost of Android Mutation Testing
- **Autoren:** Lin Deng, Jeff Offutt
- **Jahr:** 2018
- **Venue:** SEKE 2018
- **Paper-Typ:** Empirische Studie
- **Sprachen/Plattformen im Fokus:** Android (Java/Kotlin), XML-Layouts

## 2. Kernaussage
Das Paper identifiziert redundante Mutationsoperatoren in der Android-Mutation-Testing-Domäne. Durch empirische Analyse von 4 Open-Source-Android-Apps wird gezeigt, dass 3 Operatoren ausgeschlossen und mehrere andere verbessert werden können, ohne die Testeffektivität zu beeinträchtigen.

## 3. Einordnung
- **Vorarbeiten:** Baut auf priorischer Android-Mutation-Testing-Arbeit der Autoren auf (2015-2017), erweitert Selective Mutation Ansätze von Wong & Mathur
- **Kritisierte/erweiterte Ansätze:** Erweitert "do-fewer"-Strategien (selektive Mutation) auf Android-spezifische Operatoren
- **Relevanz für Framework-Design:** hoch — Identifikation redundanter Operatoren reduziert Rechenzeit um 16% ohne Effektivitätsverlust; Framework sollte Operator-Subsumption-Beziehungen modellieren

## 4. Technische Inhalte

### Mutationsoperatoren
- 19 Java-traditionelle Operatoren (muJava) + 17 Android-spezifische Operatoren
- Android-Kategorien: Event-basiert (5), Lifecycle (2), XML-related (5), Common Faults (3), Energy/Network (2)
- Redundanzanalyse basierend auf Redundancy Score: r_i,j = (Mutanten von Typ j getötet durch Test_i) / (Gesamtzahl nicht-äquivalenter Mutanten Typ j) × 100%

### Architektur & Implementierung
- Ebene: Source-Level (Java + XML-Layout-Dateien)
- Tool: muJava für Java, eigene Android-Mutation-Testing-Framework
- Multithreading-Controller für Parallelisierung (8 Emulatoren + 12 reale Motorola MOTO G Devices)

### Kostensenkung & Performance
- 16% Reduktion der Mutantenanzahl für Tipster nach Operator-Ausschlüssen
- Ausgeschlossene Operatoren: AODU (77.1% average redundancy), AOIU, LOI, MDL (sollte verbessert werden)
- Subsumption-Beziehungen: BWS subsumiert BWD; ODL subsumiert CDL, COD, VDL

### Equivalent-Mutant-Problem
- Manuelle Equivalent-Mutant-Erkennung durch Tester
- Identifikation schwer zu tötender Mutanten: FOB (6.4%), TVD (<1%), ORL (2.5%) durchschnittliche Redundancy Scores

### Skalierbarkeit & Integration
- Experimentelle Subjekte: 12 Android-Klassen aus 4 Open-Source-Apps (insgesamt 2.144 LOC)
- Erzeugung: 1.947 muJava + 1.018 Android-Mutanten
- Automatisierte Redundancy-Score-Berechnung über alle Subjects

## 5. Empirische Befunde
- **Testsubjekte/Benchmarks:** JustSit, MunchLife, TippyTipper, Tipster (alle Open-Source auf GitHub)
- **Methodik:** 4-Schritte-Prozess (Mutanten erzeugen, Äquivalente eliminieren, Tests designen, Redundancy Scores berechnen)
- **Zentrale Ergebnisse:**
  - 3 Operatoren vollständig redundant (AODU, AOIU, LOI)
  - MDL erzeugt triviale Mutanten → Redesign empfohlen
  - Subsumption-Beziehungen identifiziert
  - Re-Evaluation auf Tipster: 16% Mutant-Reduktion, gleiche Fault-Detection-Effektivität (51/64 faults)

## 6. Design-Implikationen für mein Framework
- **Operator-Redundanz-Analyse:** Framework sollte automatisierte Redundancy-Score-Berechnung unterstützen
- **Subsumption-Modeling:** Modeliierung von Operator-Subsumption-Beziehungen zur automatischen Operator-Ausschluss-Empfehlung
- **Platform-spezifische Operatoren:** Android-Framework braucht separate Operator-Taxonomie (Event, Lifecycle, XML)
- **Equivalent-Mutant-Handling:** Semi-automatische Equivalent-Mutant-Erkennung für mobile Plattformen
- **Trivial-Mutant-Filter:** Erkennung und Filterung von Mutanten, die vor dem Testen bereits trivial sind (z.B. Resource-ID-Änderungen)

## 7. Offene Fragen & Limitationen
- **Limitationen:**
  - Kleine Testpopulation (4 Apps)
  - Manuelle Equivalent-Mutant-Erkennung fehleranfällig
  - Android-geräteabhängige Ausführung (nur KitKat getestet)
  - Keine Untersuchung höherer Order Mutants

- **Unbeantwortete Fragen:**
  - Transferierbarkeit auf andere Mobile Plattformen (iOS, Windows Mobile)?
  - Wie ändern sich Redundancy Scores über Zeit in evolving Software?
  - Welche Rolle spielen App-Komplexität und Feature-Nutzung?
