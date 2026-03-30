# RegularMutator: A Mutation Testing Tool for Solidity Smart Contracts

## 1. Metadaten
- **Titel:** RegularMutator: A Mutation Testing Tool for Solidity Smart Contracts
- **Autoren:** Y. Ivanova, A. Khritankov
- **Jahr:** 2020
- **Venue:** 9th International Young Scientist Conference on Computational Science (Procedia Computer Science)
- **Paper-Typ:** Tool-Paper + Empirische Studie
- **Sprachen/Plattformen im Fokus:** Solidity, Ethereum Smart Contracts, Blockchain

## 2. Kernaussage
RegularMutator ist ein Mutation-Testing-Tool für Solidity Smart Contracts, das klassische Mutationsoperatoren mit spezifischen Blockchain-Operatoren kombiniert. Das Tool wurde an einem großen produktiven Smart-Contract-Projekt validiert und zeigt, dass Mutation Testing gegenüber Line Coverage eine bessere Metrik für Testqualität bietet.

## 3. Einordnung
- **Vorarbeiten:** Baut auf klassischen Mutationsoperatoren (Amman/Offutt) auf; erweitert Ansätze für Smart-Contract-Domain (DAO-Vulnerabilities, Blockchain-spezifische Fehler)
- **Kritisierte/erweiterte Ansätze:** Existierende Smart-Contract-Analyseverfahren (Oyente, Securify, Mythril) konzentrieren sich auf Vulnerability Detection, nicht auf Testqualitätsbewertung
- **Relevanz für Framework-Design:** **mittel-hoch** — Demonstriert domänenspezifische Anpassung von Mutation Testing auf neue Sprachen/Domains (Blockchain); wichtig für Framework-Extensibilität und Language Support.

## 4. Technische Inhalte

### Mutationsoperatoren
1. **Klassische Operatoren (Standard):**
   - Absolute Value Insertion (ABS): Arithmetische Ausdrücke modifizieren
   - Relational Operator Replacement (ROR): <, ≤, >, ≥, == durch andere ersetzen
   - Arithmetic Operator Replacement (AOR): +, −, ∗, /, ∗∗, % durch andere ersetzen
   - Conditional Operator Replacement (COR): and/or durch andere Operator ersetzen
   - Line Deletion: Ganze Quelltextzeile löschen

2. **Solidity-spezifische Operatoren (20+):**
   - Boolean Literals: true ↔ false
   - Type Changes: uint ↔ int, ufixed ↔ fixed, int-Größen (int8↔int16↔int32↔int64)
   - Memory/Storage: memory ↔ storage
   - Function State: view ↔ pure, constant ↔ pure
   - Address/Sender: msg.sender ↔ tx.origin
   - Value: msg.value ↔ 0, msg.value ↔ 1
   - Time Units: seconds↔minutes↔hours↔days↔weeks↔years
   - Time Reference: block.timestamp ↔ 0
   - Math Operations: addmod ↔ mulmod, call ↔ delegatecall, etc.

### Architektur & Implementierung
- **Ebene:** Source-Code-Level (Solidity)
- **Tool:** RegularMutator (Python-basiert), integriert mit Truffle Framework
- **Implementierungstechnik:** Regular Expressions für Mutation Injection
- **Ablauf:**
  1. Mutation Generierung mittels Regex-Substitution
  2. Mutante Dateien ersetzen Original in Projekt
  3. Testausführung für jede Mutante
  4. Status-Zuweisung: SURVIVED / KILLED / COMPILATION ERROR
  5. Mutation Score Berechnung (Killed / (Killed + Survived))

### Kostensenkung & Performance
- **Computational Cost:** ~50 Maschinenzeiten für ein großes Projekt (129 Dateien, 871 Mutanten)
- **Compilation Overhead:** 736 von 871 Mutanten (84,5%) führten zu Compilation Errors (reguläre Expression generieren syntaktisch ungültige Mutanten)
- **Performance-Problem:** Regex-basierte Mutation ineffizient; AST-basierte Mutation als Future Work vorgeschlagen
- **Operator-Selektion:** Empfohlene Optimierung: nur effektive Operatoren verwenden (ROR und Solidity-spezifisch)

### Equivalent-Mutant-Problem
Nicht thematisiert in diesem Paper.

### Skalierbarkeit & Integration
- **Testprojekt:** POA Bridge Smart Contracts v5.0.0-rc0 (129 Dateien, 96% Line Coverage, 871 Mutanten)
- **Integration:** Direkt mit Truffle Framework (Standard für Solidity-Entwicklung)
- **Automatisierung:** Vollständig automatisiert; keine manuelle Spezifikation wie bei formalen Verifikationstools

## 5. Empirische Befunde
- **Testsubjekte/Benchmarks:** 1 großes produktives Projekt (POA Bridge), Fehleranalyse basiert auf 100 GitHub-Projekten mit Smart Contracts
- **Methodik:**
  - RQ1: Ist Mutation Testing auf Smart Contracts anwendbar?
  - RQ2: Welche Operatoren sind effektiv?
  - RQ3: Vergleich Mutation Score vs. Line Coverage

- **Zentrale Ergebnisse:**
  1. **Mutation Score deutlich niedriger als Line Coverage:**
     - Line Coverage: 96%
     - Mutation Score: 18,5% (110 survived, 25 killed von 135 gültigen Mutanten)
  2. **Effektivität der Operatoren:**
     - Most Effective: Relational Operator Replacement (ROR) — 18% Survival
     - Most Effective: Solidity-Specific Operators — 26% Survival
     - Ineffektiv: viele klassische Operatoren bei Smart Contracts
  3. **Testqualität-Verbesserung möglich:** Manuelle Analyse von 50 Mutanten zeigt praktische Testdefizite
  4. **Fehlertypen identifiziert:** Conditional Logic Errors, Parameter Type Errors (z.B. != vs. > in require-Statements)
  5. **Compilation Error Rate:** 84,5% — großes Problem mit Regex-basierter Mutation

## 6. Design-Implikationen für mein Framework
1. **Domänenspezifische Operatoren essentiell:** Klassische Operatoren allein nicht ausreichend; jede neue Sprache/Domain benötigt maßgeschneiderte Operatoren
2. **Fehlerbasierte Operatorauswahl:** Empirische Analyse realer Fehler (100 Projekte durchgearbeitet) als Leitfaden für Operatoren
3. **AST-basierte Mutation bevorzugt:** Regex ist einfach zu implementieren, führt aber zu hohen Compilation-Error-Raten; AST-Mutation reduziert invalid Mutants
4. **Sprachspezifische Besonderheiten:** Blockchain-spezifische Konzepte (msg.sender, block.timestamp, gas) erfordern spezielle Operatoren
5. **Mutation Score als Testqualitäts-Indikator:** Line Coverage ist irreführend (hier 96% Coverage bei nur 18,5% Mutation Score); Mutation Score ist aussagekräftige Metrik
6. **Integration mit bestehenden Tools:** Nähe zu Truffle/Ecosystem für praktische Adoption wichtig

## 7. Offene Fragen & Limitationen
- **Limitationen:**
  - Evaluation nur auf 1 Projekt; größere empirische Basis nötig
  - Regex-basierte Implementierung ist ineffizient (84,5% Compilation Errors); AST-Ansatz notwendig
  - Manuelle Mutanten-Analyse zeitaufwändig (50 von 871 Mutanten untersucht)
  - Kein Equivalent-Mutant-Handling
  - Keine Comparison mit anderen Smart-Contract-Testing-Tools (SolAnalyser, etc.) auf gleicher Basis

- **Unbeantwortete Fragen:**
  - Wie viele Mutanten sind minimal notwendig für hohe Testqualität?
  - Welche Operatoren lassen sich kombinieren/gewichten?
  - Wie transferieren sich Erkenntnisse auf andere Blockchain-Sprachen (Rust, Move)?
  - Kann man Equivalent Mutants in Smart Contracts automatisch erkennen?
