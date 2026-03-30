# Predicting Mutation Score Using Source Code and Test Suite Metrics

## 1. Metadaten
- **Titel:** Predicting Mutation Score Using Source Code and Test Suite Metrics
- **Autoren:** Kevin Jalbert, Jeremy S. Bradbury
- **Jahr:** 2012
- **Venue:** Software Quality Research Group, University of Ontario Institute of Technology
- **Paper-Typ:** Empirische Studie
- **Sprachen/Plattformen im Fokus:** Java (Javalanche Tool)

## 2. Kernaussage
Das Paper schlägt einen Machine-Learning-Ansatz vor, um Mutation Scores vorherzusagen basierend auf Source Code und Test Suite Metriken, ohne Mutanten auszuführen. Support Vector Machines (SVM) mit 32 Features erzielen 58-59% Accuracy bei 3-Klassen-Klassifikation (Low/Medium/High), was 24-21% über Random liegt und Cost-Reduktion bei iterativer Test-Verbesserung ermöglicht.

## 3. Einordnung
- **Vorarbeiten:**
  - Cost-Reduktion Strategien: "Do fewer" (selective mutation), "Do smarter" (weak mutation), "Do faster" (schema-based mutation)
  - Software-Metriken zur Fault-Prediction (Koru et al., Gyimothy et al.)
  - Machine Learning für Software Engineering (SVM, Logistic Regression)
- **Kritisierte/erweiterte Ansätze:**
  - Selective Mutation: Reduziert Operatoren, nicht Execution Time
  - Weak Mutation: Approximation, ungenauer
  - Schema-based: Kompliziert zu implementieren
  - Neue Kategorie: "Do fewer and smarter" via predictive metrics
- **Relevanz für Framework-Design:** mittel — Prädiktive Metriken-basierte Klassifikation könnte in iterativen Workflows integriert werden

## 4. Technische Inhalte

### Mutationsoperatoren
- Javalanche Subset (7 method-level operators):
  - Replace Constant
  - Negate Jump
  - Arithmetic Replace
  - Remove Call
  - Replace Variable
  - Absolute Value
  - Unary Operator

### Architektur & Implementierung
- **Machine Learning:**
  - **Algorithm:** Support Vector Machines (LIBSVM v3.11)
  - **Problem:** 3-Klassen-Klassifikation (Low/Medium/High)
  - **Kategorisierung:** Data-driven (je 33% der Trainingsdaten in eine Klasse)
    - Beispiel (JGAP): Low 0-62.75%, Medium 62.75-83.25%, High 83.25-100%

- **Features (32 total, 4 Sets):**

  **Set Ø - Source Code Metrics (14):**
  - MLOC (Method Lines of Code)
  - NBD (Nested Block Depth)
  - VG (McCabe Cyclomatic Complexity)
  - PAR (Number of Parameters)
  - NORM, NOF, NSC, DIT, LCOM, NSM, NOM, SIX, WMC, NSF

  **Set ≠ - Coverage Metrics (2):**
  - BCOV (Basic Blocks Covered)
  - BTOT (Total Basic Blocks)

  **Set Æ - Accumulated Code Metrics (8):**
  - Sums und Averages von Code Metrics pro Class
  - SMLOC, SNBD, SVG, SPAR, AMLOC, ANBD, AVG, APAR

  **Set Ø - Test Case Metrics (8):**
  - MLOC, NBD, VG, PAR for Test Methods
  - Averages und Sums der Test-Metriken

- **Tools:**
  - Javalanche (v0.4): Mutation Testing für Java
  - Eclipse Metrics Plugin (v1.3.8): Source Code Metrics
  - EMMA (v2.0.5312): Test Coverage Metrics
  - LIBSVM (v3.11): Machine Learning Classification

- **Training Process:**
  1. Generiere Mutanten mit Javalanche
  2. Sammle Source Code Metriken (Eclipse Metrics)
  3. Sammle Coverage Metriken (EMMA)
  4. Teile Mutation Scores in Low/Medium/High
  5. Trainiere SVM mit Features
  6. Verwende für Vorhersage neuer Mutation Scores

### Kostensenkung & Performance
- **Cost Reduction Goal:** Iteration während Test-Entwicklung ohne volle Mutation Testing
- **Prediction Speed:** Microsekunden pro Unit (vs. Minuten für volle Mutation Testing)
- **Accuracy:** 58,27% (Classes), 54,82% (Methods) → 24-21% über Random
- **Time Savings:** Wenn iterativ, könnte erhebliche Zeiteinsparung durch Vorhersage statt Execution in Zwischen-Iterationen

### Equivalent-Mutant-Problem
- **Nicht explizit behandelt**
- Vorhersage umgeht Problem: Es werden nicht alle Mutanten ausgeführt
- Äquivalente Mutanten könnten in "High" Kategorie falsch klassifiziert werden

### Skalierbarkeit & Integration
- **Single Project:** Training und Prediction auf gleichen Projekten
- **No Cross-Project:** Modelle generalisieren nicht zwischen Projekten
- **Local Models Preferred:** Jedes Projekt braucht sein eigenes Modell
- **Integrierbarkeit:** Mit Javalanche kompatibel, Java-Projekte

## 5. Empirische Befunde
- **Testsubjekte:**
  - JGAP (Genetic Algorithms Framework)
  - 415 Classes, 3017 Methods
  - 13,871 JUnit Tests (1,412 test cases)

- **Methodik:**
  - Mutation Score Distribution Analysis (Figures 2&3)
  - 10-fold Cross-Validation
  - Feature Set Evaluation (4 separate feature sets)
  - Individual vs. Combined Feature Performance

- **Zentrale Ergebnisse:**
  - **Overall Accuracy:** 58.27% (classes), 54.82% (methods) — 10-fold CV
  - **Feature Importance:**
    - Source Code Metrics: 53.54% (classes), 48.77% (methods)
    - Coverage Metrics: 49.61% (classes), 47.63% (methods)
    - Accumulated Metrics: 45.67% (classes), 49.78% (methods)
    - Test Case Metrics: 54.33% (classes), 33.96% (methods)
    - **Combined (all):** 58.27% (classes), 54.82% (methods) — slight improvement
  - **Confusion Matrix:** More errors in Medium category (imbalanced classification)
  - **Distribution:** Mutation Scores heavily biased toward high values → data imbalance

## 6. Design-Implikationen für mein Framework
1. **Metrics Collection:** Framework sollte systematisch Code- und Test-Metriken sammeln
2. **SVM Integration:** Optional Predictive Mode mit trainierten Modellen
3. **Local Models:** Pro-Project Modelle trainieren, nicht cross-project
4. **Feature-Based Profiling:** Framework internals sollte diese 32 Features berechnen können
5. **Iterative Workflow:** Integration in iterative Test-Improvement-Prozesse
6. **Data-Driven Categorization:** Kategorisierung von Low/Medium/High adaptiv basierend auf Projekt-Daten

## 7. Offene Fragen & Limitationen
- **Cross-Project Failure:** Modelle generalisieren nicht zwischen Projekten → massive Limitation
- **Category Imbalance:** Mutation Scores biased toward High → Class imbalance in Training
- **Low Accuracy:** 54-58% nicht besonders hoch für praktische Vorhersagen
- **Feature Redundancy:** Nicht klar welche Features am wichtigsten sind
- **Equivalent Mutants:** Klassifikation "High" könnte durch äquivalente Mutanten inflated sein
- **Single Project Case Study:** Nur JGAP evaluiert; Generalisierung unklar
- **OO Operators:** Plan OO-Operatoren zu integrieren, aber nicht im Paper

## 8. Weitere Bemerkungen
- Paper markiert frühe Exploration des "Do fewer and smarter" Ansatzes
- Später papers (Zhang et al. 2016 - Predictive MT) zeigen bessere Ergebnisse mit anderen Features/Modellen
- Foundation für machine-learning basierte Cost-Reduktion, aber limitations sind erheblich
