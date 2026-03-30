# Mutation Testing

## 1. Metadaten
- **Titel:** Mutation Testing
- **Autoren:** Gordon Fraser (Saarland University)
- **Jahr:** 2010
- **Venue:** Software Engineering (Lehrbuch-Kapitel / Vorlesungsfolien)
- **Paper-Typ:** Lehrbuch / Einführung
- **Sprachen/Plattformen im Fokus:** C, Java (OO Mutation), allgemeine Konzepte

## 2. Kernaussage
Umfassende Einführung in Mutation-Testing-Konzepte für Lehr- und Lernzwecke. Vermittelt praktisches Verständnis von Mutationsoperatoren, der Mutation Testing-Methodik und fundamentalen Hypothesen durch erklärende Beispiele und visuelle Darstellung.

## 3. Einordnung
- **Vorarbeiten:** Bezieht sich auf klassische Mutation-Testing-Theorie (CPH, Coupling Effect)
- **Kritisierte/erweiterte Ansätze:** Nicht primary; konzentriert sich auf Wissensvermittlung
- **Relevanz für Framework-Design:** hoch — Praktische Referenz für Mutationsoperatoren-Implementation, OO-Mutation und Mutation Analysis/Testing-Unterscheidung

## 4. Technische Inhalte

### Mutationsoperatoren
- **Grundlegende Kategorien:**
  - **ABS (Absolute Value Insertion):** Einfügung von abs() um Variablen oder Rückgabewerte
  - **AOR (Arithmetic Operator Replacement):** Ersetzung von +, -, *, /, %, ** inkl. Operanden-Elimination (x+y → x oder y)
  - **ROR (Relational Operator Replacement):** Ersetzung von <, >, <=, >=, ==, != sowie Ersetzung durch true/false
  - **COR (Conditional Operator Replacement):** &&, ||, &, |, ^ sowie if(a), if(b)
  - **SOR (Shift Operator Replacement):** <<, >>, >>>
  - **LOR (Logical Operator Replacement):** &, |, ^
  - **ASR (Assignment Operator Replacement):** +=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>=, >>>=
  - **UOI (Unary Operator Insertion):** +, -, !, ~, ++, --
  - **UOD (Unary Operator Deletion):** Entfernung unärer Operatoren
  - **SVR (Scalar Variable Replacement):** Austausch einer Variable durch andere (z.B. x ↔ y, tmp)

- **Object-Oriented Mutation Operatoren:**
  - AMC (Access Modifier Change): protected ↔ private
  - HVD (Hiding Variable Deletion), HVI (Hiding Variable Insertion)
  - OMD (Overriding Method Deletion)
  - OMM (Overridden Method Moving), OMR (Overridden Method Rename)
  - SKR (Super Keyword Deletion)
  - PCD (Parent Constructor Deletion)
  - ATC (Actual Type Change), DTC (Declared Type Change), PTC (Parameter Type Change), RTC (Reference Type Change)
  - OMC (Overloading Method Change), OMD (Overloading Method Deletion)
  - AOC (Argument Order Change), ANC (Argument Number Change)
  - TKD (this Keyword Deletion), SMV (Static Modifier Change)
  - VID (Variable Initialization Deletion)
  - DCD (Default Constructor Deletion)

- **Interface Mutation (Integration-Level):**
  - Modifikation von Werten an Method-Boundaries
  - Änderung von Call-Statements
  - Modifikation von Return-Statements

### Architektur & Implementierung
- **Mutationen-Ebenen:**
  - First-Order Mutants (FOM): Genau eine syntaktische Änderung
  - Higher-Order Mutants (HOM): Mehrfache Mutationen; Anzahl HOM ~ 2^(#FOM - 1)
- **Prozess:** Original-Programm → Mutant-Generierung → Test-Ausführung → Tötungs-Status Bestimmung
- **Test-Oracle-Problem:** Kritisch — reichte Coverage allein nicht aus; tatsächliche Assertion-Checks notwendig

### Kostensenkung & Performance
Nicht direkt thematisiert; fokussiert auf Grundlagen.

### Equivalent-Mutant-Problem
- **Definition:** Syntaktische Änderung ändert nicht die Semantik
- **Ursachen:**
  - Keine Erreichbarkeit (Reachability)
  - Erreichbar, aber keine Infektion (Infection)
  - Infektion, aber keine Propagation (Propagation)
- **Komplexität:** Undecidable Problem (NP-vollständig)

### Skalierbarkeit & Integration
Nicht thematisiert; konzentriert sich auf grundlegende Konzepte.

## 5. Empirische Befunde
- **Testsubjekte:** Illustrative Code-Beispiele (z.B. gcd(), max())
- **Methodik:** Hands-on Demonstration von Mutanten und deren Tötung durch Tests
- **Zentrale Ergebnisse:**
  - Mutation Score = (Killed Mutants) / (Total Mutants)
  - Unterscheidung: Mutation Analysis (Qualitätsbewertung) vs. Mutation Testing (Qualitätsverbesserung)
  - Competent Programmer Hypothesis und Coupling Effect rechtfertigen First-Order Fokus

## 6. Design-Implikationen für mein Framework
- **Mutationsoperatoren-Katalog:** Systematische Taxonomie mit konkreten Implementierungsbeispielen für jede Klasse
- **Language-Specific Operatoren:** OO-Mutation für Java/C#, Basis-Operatoren für alle Sprachen, Interface-Mutation für Integration Testing
- **Mutation Grading:** Clear API zur Bestimmung von Tötungs-Status und Mutation Score
- **Test-Oracle:** Framework muss nur Assertion-Failures registrieren, nicht Code-Coverage allein relieren
- **Equivalent Mutant Hints:** Visuelle oder analytische Hinweise zur Erkennung potentiell äquivalenter Mutanten
- **Beispiele und Dokumentation:** Ausführliche Code-Beispiele für jede Operator-Klasse zur Benutzer-Schulung

## 7. Offene Fragen & Limitationen
- **Limitationen:** Lehrbuch-Fokus; keine empirischen Studien oder Performance-Messungen
- **Offene Fragen:**
  - Wie implementiert man OO-Mutation korrekt und vollständig?
  - Welche Operatoren sind für welche Sprachen/Domänen optimal?
  - Wie unterscheidet man automatisch äquivalente Mutanten?
