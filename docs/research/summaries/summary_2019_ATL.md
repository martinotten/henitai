# Towards effective mutation testing for ATL

## 1. Metadaten
- **Titel:** Towards effective mutation testing for ATL
- **Autoren:** Esther Guerra, Jesús Sánchez Cuadrado, Juan de Lara
- **Jahr:** 2019
- **Venue:** IEEE (32nd International Conference on Software Engineering and Knowledge Engineering)
- **Paper-Typ:** Empirische Studie + Tool-Paper
- **Sprachen/Plattformen im Fokus:** ATL (ATLAS Transformation Language), Model-Driven Engineering

## 2. Kernaussage
Das Paper evaluiert die Effektivität von Mutationsoperatoren für ATL-Transformationen und schlägt neue Operatoren vor, die auf empirischen Fehleranalysen basieren. Zusätzlich wird eine automatisierte Technik zur Erzeugung von Testmodellen entwickelt, die lebende Mutanten töten.

## 3. Einordnung
- **Vorarbeiten:** Baut auf Mutation-Testing-Pionierarbeiten (DeMillo et al.) auf; entwickelt Ansätze von Troya et al., Mottu et al., Sánchez et al. und Khan et al. für ATL weiter
- **Kritisierte/erweiterte Ansätze:** Existierende ATL-Operatoren (syntaktisch, semantisch, typisierungsorientiert) berücksichtigen keine empirischen Fehleranalysen; keine automatisierten Verfahren zur Testmodell-Synthese vorhanden
- **Relevanz für Framework-Design:** **hoch** — Das Paper liefert domänen-spezifische Mutationsoperatoren und demonstriert eine empirische Methodik zur Operatorauswahl, die auf Fehleranalysen basiert; besonders relevant für DSL-basierte Transformation und Operatordesign.

## 4. Technische Inhalte

### Mutationsoperatoren
- **Syntaktische Operatoren (18):** Basiert auf CUD-Operationen (Create, Update, Delete) auf Meta-Modell-Elementen (Troya et al.); umfasst Regel-Addition/Deletion, Pattern-Element-Addition/Deletion, Filter- und Binding-Modifikationen
- **Semantische Operatoren (10):** Von Mottu et al.; adressiert OCL-Navigationsfehler (RSCC, ROCC, RSMD, RSMA), Filterfehler (CFCP, CFCD, CFCA), Kreationsfehler (CCCR, CACD, CACA)
- **Typisierungsoperatoren (27):** Von Sánchez et al.; injiziert Typisierungsfehler (Binding-Creation/Deletion, Type-Modification, Parameter-Modifikation, etc.)
- **Zoo-Operatoren (7 neu):** Basiert auf Analyse von 101 realen Transformationen aus ATL Zoo; adressiert häufigste Entwicklerfehler:
  - RBCF (Remove Binding of Compulsory Feature): 44,8% der realen Fehler
  - RHCP (Replace Helper Call Parameter): 11,9%
  - REC (Remove Enclosing Conditional): 11,2%
  - ANAOF (Add Navigation After Optional Feature): 11,2%
  - RSF (Replace Feature Access by Subtype Feature): 3,75%
  - RRF (Restrict Rule Filter): 3,7%
  - DR (Delete Rule): 3,7%

### Architektur & Implementierung
- **Ebene:** AST-Level (Abstract Syntax Tree); betrifft Transformation-Code direkt
- **Tool:** Java-Framework (Open-Source verfügbar), nutzt EMF, anATLyzer static analyzer
- **Kernkomponenten:**
  1. MutationRegistry: Verwaltung aller Operatoren als erweiterbare Klassen
  2. MutantGenerator: Anwendung von Mutationsoperatoren auf Transformations-AST
  3. ModelGenerator: Synthese von Testmodellen für lebende Mutanten mittels USE Validator
  4. DifferentialTester: Vergleicht Ausgaben Original vs. Mutant
- **Algorithmus für Testmodell-Synthese:**
  - Berechnet OCL-Pfadbedingungen, die mutierte Code-Stellen erreichen
  - Nutzt Alloy/USE-Validator als Modell-Finder
  - Konvertiert Kontrollfluss-Graph zu OCL-Constraints

### Kostensenkung & Performance
- **Operator-Effizienz:** Zoo-Operatoren erzeugen 2-3x weniger Mutanten bei ähnlicher Effektivität (z.B. RBCF vs. BindingDeletionMutator: 260 vs. 724 Mutanten)
- **Selective Mutation:** Identifikation trivial-einfacher Operatoren zur Kostenreduktion (bis zu 75%)
- **Testmodell-Reduktion:** Transformation Path Coverage generiert weniger Modelle als Meta-Model Coverage, mit höherer Effektivität

### Equivalent-Mutant-Problem
- **Referenzierung:** Problem explizit erwähnt, heuristische Lösungen erwähnt (Constraints, Binary-Vergleich, Automata-Sprachäquivalenz)
- **Praxis:** Wird in der Evaluation berücksichtigt durch Vergleich Original vs. Mutant-Output; keine spezifische Vermeidungsstrategie implementiert

### Skalierbarkeit & Integration
- **Große Codebases:** Evaluation auf 6 realen ATL-Transformationen aus ATL Zoo
- **Operator-Anwendbarkeit:** >61% der Operatoren auf alle Transformationen anwendbar; einige spezialisiert (z.B. nur auf Transformationen mit Regel-Erbschaft)
- **Evaluationsumfang:** >32.000 mutierte Transformationen, >1 Million Transformations-Ausführungen

## 5. Empirische Befunde
- **Testsubjekte/Benchmarks:** 6 ATL-Transformationen (class2table, uml2intalio, bt2db, cpl2spl, hsm2fsm, uml2er); Fehleranalyse basiert auf 101 Transformationen aus ATL Zoo
- **Methodik:**
  - RQ1: Vergleich Hardness-to-Kill aller Operatoren über alle Transformationen
  - RQ1.1: Zoo-Operatoren vs. andere Operatoren
  - RQ2: Vergleich drei Testmodell-Generierungstechniken (random, Meta-Model Coverage, Transformation Path Coverage)
  - RQ3: Effektivität der Testmodell-Synthese für lebende Mutanten

- **Zentrale Ergebnisse:**
  1. **Operator-Killing-Raten:**
     - Leicht zu töten (>99%): CACA, RSMD, RSCC, Filter-Addition
     - Schwer zu töten (<90%): Typing-Operatoren (52-55), besonders HelperReturnModificationMutator (91,3%), ParameterDeletion (89,5%)
  2. **Zoo-Operatoren:** Gemischte Ergebnisse; AddNavigationAfterOptionalFeature (55) schwer zu töten (83,3%), andere aber leicht
  3. **Testmodell-Generierung:**
     - Path-based Coverage: 100% Oracle-Killed für alle Operatoren
     - Meta-Model Coverage: 80% der Operatoren
     - Random: nur 36% der Operatoren
  4. **Mutant-Stubbornness:** Durchschnittlich nur 18-26% der Testmodelle töten einen Mutanten (sehr stubborn)
  5. **Synthesiseffektivität:** Automatisch generierte Modelle können ~85% der lebenden Mutanten töten

## 6. Design-Implikationen für mein Framework
1. **Empirische Operatorauswahl:** Mutationsoperatoren sollten auf Fehleranalysen realer Code-Artefakte basieren, nicht nur auf Meta-Modell-Coverage
2. **Domänen-spezifische Operatoren:** Verschiedene Domänen (DSL, klassischer Code, Transformationen) erfordern maßgeschneiderte Operatorsets; Operatoren sind nicht universell
3. **Operator-Klassifikation:** Drei Dimensionen nützlich: Syntaktisch (auf Meta-Modell-Strukturen), Semantisch (Fehlertypen), Empirisch (häufige Entwicklerfehler)
4. **Testmodell-Synthese:** Automatisierte Synthese über Constraint-Solving (OCL-Pfadbedingungen) ist praktisch und vielversprechend
5. **Test-Generierungstechnik kritisch:** Path-Coverage generiert bessere Testmodelle als Meta-Model oder Random Coverage
6. **Operator-Effizienz-Analyse notwendig:** Regelmäßige Evaluierung von Operatoren auf ihre Killing-Rate; triviale Operatoren ausschließen

## 7. Offene Fragen & Limitationen
- **Limitationen:**
  - Evaluation auf nur 6 Transformationen; größere empirische Basis nötig
  - Synthesisverfahren nicht garantiert, dass Generated Models tatsächlich Mutanten töten (nur notwendig, nicht hinreichend)
  - Fokus auf ATL; Generalisierbarkeit zu anderen Transformationssprachen unklar
  - Typisierungsfehler sind sprachspezifisch; andere Domänen haben unterschiedliche Fehlermuster

- **Unbeantwortete Fragen:**
  - Wie sollten Operatoren gewichtet werden, wenn mehrere Operatoren ähnliche Fehler adressieren?
  - Welche minimale Operatormenge ist für "gute" Mutation Testing ausreichend?
  - Wie transferieren sich Erkenntnisse auf andere DSLs und Transformationssprachen?
