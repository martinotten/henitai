# Performance Mutation Testing

## 1. Metadaten
- **Titel:** Performance Mutation Testing
- **Autoren:** Pedro Delgado-Pérez, Ana B. Sánchez, Sergio Segura, Inmaculada Medina-Bulo
- **Jahr:** 2010
- **Venue:** Software Testing, Verification and Reliability (Wiley)
- **Paper-Typ:** Theoretisch, Tool-Paper
- **Sprachen/Plattformen im Fokus:** C++

## 2. Kernaussage
Das Paper überträgt das Konzept der klassischen Mutation Testing auf Performance-Tests. Es werden sieben neuartige Mutationsoperatoren vorgestellt, die Leistungsprobleme in C++-Programmen modellieren, um die Effektivität von Performance-Test-Suites zu bewerten und zu verbessern.

## 3. Einordnung
- **Vorarbeiten:** Basiert auf klassischem Mutation Testing (Offutt et al., DeMillo et al.); erweitert Ansätze aus Android und modellgestützten Operatoren
- **Kritisierte/erweiterte Ansätze:** Zeigt, dass Mutation Testing nicht nur für Funktionalität, sondern auch für nicht-funktionale Eigenschaften wie Performance genutzt werden kann
- **Relevanz für Framework-Design:** Hoch — bietet konkrete Operatoren und hebt heraus, dass Performance-Mutanten semantisches Äquivalenzproblem fundamental anders adressieren müssen

## 4. Technische Inhalte

### Mutationsoperatoren
Das Paper definiert sieben Performance-Mutationsoperatoren, alle auf klassischen Performance-Bug-Patterns basierend:

1. **RCL (Removal of Stop Condition in Loop):** Entfernt Break- oder Bedingungsanweisungen in Schleifen
2. **URV (Unnecessary Recalculation of Values):** Erzwingt Neuberechnung bereits gerechneter Werte
3. **MSL (Move/Copy Statement into Loop):** Verschiebt Objekt-Generierung oder Bedingungen in Schleife
4. **SOC (Swap of Operands in Condition):** Tauscht Operanden in Bedingungen (zeitkostiger zuerst)
5. **HWO (Hide a Function Call in While Loop):** Versteckt Function Calls in While-Bedingungen
6. **CSO (Copy Statement out of Loop):** Kopiert Statements aus Schleife (und verändertsie)
7. **MSR (Modify Statement in Collections):** Manipuliert Collection-Operationen

Jeder Operator ist mit Vorbedingungen ausgestattet, um semantische Gleichwertigkeit zu vermeiden.

### Architektur & Implementierung
- **Ebene:** Source-Code-Level für C++
- **Ansatz:** Code-basierte Mutation über Vorbedingungen und Analyse
- **Problem:** Compiler-Optimierungen könnten Performance-Mutationen automatisch rückgängig machen

### Kostensenkung & Performance
- Nicht primär Fokus, aber Paper zeigt, dass über 80% der erzeugten Performance-Mutanten nicht durch funktionale Test-Suites erkannt werden (vs. 42,7% bei traditionellen Mutanten)
- Dies ist positiv, da Performance-Mutanten semantisches Verhalten bewahren sollen

### Equivalent-Mutant-Problem
Fundamentales Unterscheidungsmerkmal zu klassischem MT: **Semantisch-äquivalente Mutanten sind das Ziel von PMT, nicht das Hindernis**. Ein Mutant ist gültig, wenn er Leistungsdegradation verursacht, ohne Funktionalität zu ändern. Dies schafft praktische Herausforderungen bei Compiler-Optimierungen.

### Skalierbarkeit & Integration
Fokus auf Machbarkeit auf echten Open-Source-C++-Programmen. Experiment mit 241 Mutanten zeigt praktisches Potential, jedoch begrenzte Evaluierungstiefe.

## 5. Empirische Befunde
- **Testsubjekte/Benchmarks:** 3 Open-Source-C++-Programme (größere Projekte)
- **Methodik:** Manuelle Überprüfung von Live-Mutanten, Compiler-Optimisierungsanalyse, Vergleich mit traditionellen Operatoren
- **Zentrale Ergebnisse:**
  - 194 von 241 Performance-Mutanten (80,5%) nicht durch Funktionalitäts-Test-Suites erkannt
  - Traditionelle Mutanten: nur 42,7% nicht erkannt
  - Meisten Performance-Mutationen werden nicht durch Compiler-Optimierungen vereitelt
  - Performance-Degradation erfordert spezielle Test-Eingaben (Skalierbarkeit, Sequenzierungsabhängigkeiten)

## 6. Design-Implikationen für mein Framework
- **Operatoren-Katalog:** Implementierung der 7 Operatoren als modulare Bausteine mit konfigurierbare Vorbedingungen
- **Semantik-Handling:** Spezielle Behandlung von Äquivalenz bei Performance-Mutations (im Gegensatz zu funktionalen Mutations)
- **Compiler-Interaktion:** Robustheits-Tests gegen Optimierungen einplanen
- **Zielsprachenerweiterung:** Framework sollte auf andere Sprachen (Java, Python) erweiterbar sein; Operatoren sind weitgehend sprachunabhängig
- **Validierung:** Vorbedingungen helfen, ungültige Mutanten zu filtern; Fokus sollte auf realistic Performance-degradation liegen

## 7. Offene Fragen & Limitationen
- **Evaluierungsumfang:** Begrenzt auf 3 Programme und 28 Seiten Forschungsarbeit; Generalisierbarkeit unklar
- **Compiler-Variabilität:** Wie verhalten sich Optimierungen über verschiedene GCC/Clang-Versionen?
- **Definition von „bemerkenswert":** Schwellwert für Performance-Degradation ist kontextabhängig und nicht universell
- **Private Methods:** Wenig Diskussion über Mutation in nicht öffentlichen Methoden
- **Äquivalenz-Problem bleibt:**Bestimmung echter Äquivalenz bei Performance ist praktisch noch schwieriger als funktional
