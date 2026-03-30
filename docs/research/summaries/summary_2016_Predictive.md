# Predictive Mutation Testing

## 1. Metadaten
- **Titel:** Predictive Mutation Testing
- **Autoren:** Jie Zhang, Ziyi Wang, Lingming Zhang, Dan Hao, Lei Zang, Shiyang Cheng, Lu Zhang
- **Jahr:** 2016
- **Venue:** ACM ISSTA/FSE Conference
- **Paper-Typ:** Empirische Studie + Tool-Paper
- **Sprachen/Plattformen im Fokus:** Java (Evaluierung auf 163 open-source Projekten)

## 2. Kernaussage
PMT (Predictive Mutation Testing) nutzt maschinelles Lernen zur Vorhersage von Mutanten-Killing-Status ohne tatsächliche Ausführung. Durch Klassifikationsmodelle basierend auf Mutanten- und Test-Features erreicht PMT bis zu 151,4x Speedup bei minimaler Genauigkeitsverlust, wodurch Mutation Testing praktisch effizienter wird ohne empirische Testeffektivität zu opfern.

## 3. Einordnung
- **Vorarbeiten:** Bestehende Cost-Reduktion-Techniken: selective mutation, weak mutation, schema-based mutation
- **Kritisierte/erweiterte Ansätze:**
  - "Do fewer" (selective mutation): Reduziert Mutantenanzahl aber nicht Execution-Kosten
  - "Do smarter" (weak mutation): Approximation aber ungenauer
  - "Do faster" (schema-based mutation): Performance-Optimierung aber kompliziert
  - Neue Kategorie: "Do fewer and smarter" via prediction
- **Relevanz für Framework-Design:** mittel-hoch — Prädiktive Ansätze könnten in Iterative Test-Entwicklung integriert werden; alternative zu vollständiger Evaluierung

## 4. Technische Inhalte

### Mutationsoperatoren
- Javalanche subset: replace constant, negate jump, arithmetic replace, remove call, replace variable, absolute value, unary operator
- Focus auf method-level operators (most common)

### Architektur & Implementierung
- **Machine Learning Ansatz:** Support Vector Machine (SVM) via LIBSVM (v3.11)
- **Features (32 total):**
  - **Source Code Metrics (Ø set):** MLOC, NBD, VG (cyclomatic complexity), PAR, NORM, NOF, NSC, DIT, LCOM, NSM, NOM, SIX, WMC, NSF
  - **Coverage Metrics (≠ set):** Basic block coverage (BCOV, BTOT)
  - **Accumulated Code Metrics (Æ set):** Sums and averages of code metrics per class
  - **Test Case Metrics (Ø set):** MLOC, NBD, VG, PAR for test methods
- **Tools:** Eclipse Metrics Plugin, EMMA für Coverage
- **Classification:** 3-Category-Klassifikation (Low, Medium, High Mutation Score)
  - Kategorien basierend auf Datenversteilung (je 33% der Trainingsdaten)

### Kostensenkung & Performance
- **Speedup:** Bis zu 151,4x Effizienzsteigerung durch Vorhersage statt Execution
- **Accuracy Loss:** Minimal (cross-validation accuracy 54-58%)
- **Computational Cost:** Prediction sehr schnell (Microsekunden pro Mutant)
- **Trade-off:** Good balance zwischen Efficiency und Effektivität

### Equivalent-Mutant-Problem
- Nicht explizit adressiert
- Vorhersage umgeht Problem indirekt: Killing-Status wird approximiert, nicht jeder Mutant ausgeführt

### Skalierbarkeit & Integration
- **Large-scale Evaluation:** 163 open-source Projekte
- **Praktische Anwendung:** Kann iterativ eingesetzt werden während Tests entwickelt werden
- **Cross-Project Evaluation:** Limitiert (Modelle meist projekt-spezifisch)
- **Implementation:** Integrierbar mit Javalanche

## 5. Empirische Befunde
- **Testsubjekte:** 163 real-world open-source Java Projekte
- **Methodik:**
  - SVM Training mit Features aus Source Code und Test Suites
  - 10-fold Cross-Validation auf einzelnem Projekt (JGAP)
  - Zwei Szenarien: cross-version, cross-project
- **Zentrale Ergebnisse:**
  - **JGAP Case Study:**
    - 32.031 Mutanten, 18.378 covered, 13.698 killed
    - Mutation Score: 74.53%
    - Accuracy: 58,27% (classes), 54,82% (methods)
    - Outperforms random by 24,94% (classes), 21,49% (methods)
  - **Cross-version Scenario:** Sehr gute Generalisierung
  - **Cross-project Scenario:** Begrenzte Generalisierung (zu projekt-spezifisch)
  - **Feature Importance:** Kombination aller Features leicht besser als einzelne Sets

## 6. Design-Implikationen für mein Framework
1. **Prädiktive Methode als Option:** SVM-basierte Vorhersage als Alternative zu vollständiger Evaluierung für iterative Entwicklung
2. **Feature-Engineering:** Framework sollte Code- und Test-Metriken zur Klassifikation sammeln können
3. **Zwei-Szenario-Support:** Cross-version (innerhalb eines Projekts) und cross-project (zwischen Projekten) Modes
4. **Integration mit Mutanten-Scoring:** Vorhersage könnte als Snapshot während Testentwicklung dienen
5. **Warnung vor Generalisierung:** Cross-project Performance schwach → lokale Modelle bevorzugt

## 7. Offene Fragen & Limitationen
- **Cross-Project Limitation:** Modelle generalisieren schlecht zwischen Projekten
- **Kategorial vs. Kontinuierlich:** Kategorisierung (Low/Medium/High) verliert Granularität
- **Feature Selection:** Begrenzte Analyse welche Features am wichtigsten sind
- **Equivalent Mutants:** Nicht explizit behandelt in Vorhersage
- **Large Codebase:** Skalierung auf sehr große Systeme nicht untersucht
- **Weak Mutation Vergleich:** Nicht direkt mit Weak Mutation verglichen
