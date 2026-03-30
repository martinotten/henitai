# Mutation Testing Guideline and Mutation Operator Classification

## 1. Metadaten
- **Titel:** Mutation Testing: Guideline and Mutation Operator Classification
- **Autoren:** Lorena Gutiérrez-Madroñal, Juan José Domínguez-Jiménez, Inmaculada Medina-Bulo
- **Jahr:** 2014
- **Venue:** ICCGI (International Multi-Conference on Computing in the Global Information Technology)
- **Paper-Typ:** Methodologischer Leitfaden + Empirische Studie
- **Sprachen/Plattformen im Fokus:** Multiple (Fokus auf Event Processing Language, SQL-like)

## 2. Kernaussage
Das Paper stellt einen formalen Prozess-Leitfaden für Mutation Testing Studies (MTS) auf neuen Programmiersprachen auf und präsentiert eine Klassifikation von Mutation Operators in drei Sätze (SoMO): Traditional, Nature-spezifisch und Language-spezifisch. Dies ermöglicht es zu bewerten, ob ein MTS "mature" ist.

## 3. Einordnung
- **Vorarbeiten:** Mutation Testing Grundlagen (DeMillo et al., Hamlet), frühere Operator-Definitionen für Fortran/C/Java (Mathur), Operator-Studien (Offutt et al., Namin et al.), Constraint-based Test Generation
- **Kritisierte/erweiterte Ansätze:** Keine vorherige Arbeit zur Operator-Klassifikation oder Reife-Definition; neue Sprachen haben keine systematischen Richtlinien gehabt
- **Relevanz für Framework-Design:** hoch — bietet systematische Kategorisierung und Reife-Bewertungsrahmen

## 4. Technische Inhalte

### Mutationsoperatoren
- **SoMO-Klassifikation (Sets of Mutation Operators):**
  1. **Traditional Operators:** Sprach-unabhängig, in allen MTS vorhanden
     - Relational Operator Replacement (ROR)
     - Arithmetic Operator Replacement (AOR)
     - Logical Operator Replacement (LOR)
     - etc.
  2. **Nature Operators:** Sprach-natur-spezifisch
     - OO-Sprachen: Inheritance, Polymorphism Operators
     - Query-Sprachen: SELECT clause, WHERE clause Operators
     - etc.
  3. **Specific Operators:** Sprach-spezifisch, nicht auf andere Sprachen übertragbar
     - EPL: Event-Stream-spezifische Operatoren
     - GQL: Google Query Language-spezifische Operatoren
     - etc.

### Architektur & Implementierung
- **Prozess (Mutation Testing Study Guideline):**
  1. **Language Selection:** Basissprache identifizieren, Verfügbarkeit/Popularität prüfen
  2. **Grammar Study:** Ausgiebige Grammatik-Analyse; jede Code-Zeile betrachten
  3. **Mutation Operator Definition:** Basierend auf Grammatik; Kontext beachten (z.B. * als Arithmetik vs. Wildcard)
  4. **Implementation:** Mutation Operators in Tool implementieren
  5. **Classification:** Operatoren in SoMO-Set klassifizieren
  6. **Killing Criteria & Output Definition:** Festlegung, wie Mutanten als "getötet" gelten
  7. **Mutant Classification:** Bestimmung von killed/alive/stillborn/equivalent/stubborn Mutanten

### Kostensenkung & Performance
Nicht primär adressiert; fokussiert auf Struktur, nicht Optimierung.

### Equivalent-Mutant-Problem
- **Definition:**
  - **Equivalent Mutant:** Keine Test-Case kann Original und Mutant unterscheiden
  - **Stubborn Non-Equivalent:** Kein Test-Case in Test-Suite kann unterscheiden, aber mögliche Teste könnten es
- **Behandlung:** Manuelle Analyse erforderlich; Constraint-based Test Generation erwähnt

### Skalierbarkeit & Integration
- **Testsubjekte:** Demonstriert mit Event Processing Language (EPL); neue Mutation Operators definiert
- **Guidance für neue Sprachen:** Prozess ist generisch, auf alle Programmiersprachen anwendbar

## 5. Empirische Befunde
- **Testsubjekte/Benchmarks:** Event Processing Language als Fallstudie; neue EPL-Mutation Operators definiert und evaluiert
- **Zentrale Befunde:**
  - SoMO-Klassifikation erfolgreich auf EPL angewendet
  - Neue EPL-Operatoren in Specific Set klassifiziert (z.B. Event-Stream-bezogene Changes)
  - Guideline ermöglicht strukturierte MTS für neue Sprachen
  - Reife-Definition auf Basis von SoMO-Vollständigkeit möglich

## 6. Design-Implikationen für mein Framework
1. **SoMO-Klassifikation implementieren:** Framework sollte Operators nach Traditional/Nature/Specific kategorisieren
2. **Prozess-Leitfaden befolgen:** Strukturierter 7-Stufen-Prozess als Best Practice für neue Sprachen
3. **Reife-Bewertung:** Framework sollte Indikator für Operator-Vollständigkeit anbieten (SoMO-basiert)
4. **Grammatik-Analyse:** Framework könnte Assistenz bei Grammar-Study anbieten
5. **Output Definition:** Framework muss Killing Criteria flexibel definierbar machen
6. **Äquivalent-Handling:** Framework sollte Unterscheidung zwischen equivalent/stubborn non-equivalent unterstützen

## 7. Offene Fragen & Limitationen
- **Limitationen:**
  - Nur EPL als detaillierte Fallstudie; Validierung auf anderen neuen Sprachen begrenzt
  - Keine quantitative Metrik zur Reife-Definition (nur qualitative Beschreibung)
  - Manuelle Äquivalent-Erkennung bleibt aufwändig
  - Keine Evaluierung des Prozess-Aufwands (wie lange dauert MTS-Entwicklung?)
- **Offene Fragen:**
  - Wie lässt sich die Reife-Definition automatisiert bewerten?
  - Können SoMO-Sets über ähnliche Sprachen hinweg wiederverwendet werden?
  - Wie viele Specific Operators sind "genug" für verschiedene Sprachkategorien?
  - Können Nature/Specific Operators automatisch aus AST-Analyse generiert werden?
