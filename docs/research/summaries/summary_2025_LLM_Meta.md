# Mutation-Guided LLM-based Test Generation at Meta

## 1. Metadaten
- **Titel:** Mutation-Guided LLM-based Test Generation at Meta
- **Autoren:** Christopher Foster, Abhishek Gulati, Mark Harman, Inna Harper, Ke Mao, Jillian Ritchey, Hervé Robert, Shubho Sengupta (Meta Platforms)
- **Jahr:** 2025
- **Venue:** ICSE oder FSE (angenommen)
- **Paper-Typ:** Industriebericht / Tool-Paper
- **Sprachen/Plattformen im Fokus:** Kotlin/Android, Privacy-Focus

## 2. Kernaussage
Das Paper beschreibt ACH (Algorithmic Coverage Hardening), ein Meta-System für mutation-guided LLM-basierte Test-Generierung. ACH generiert gezielt wenige hochrelevante Mutanten für spezifische Bedenken (z.B. Datenschutz), erzeugt Tests zum Töten dieser Mutanten und hat auf 10.795 Android-Klassen 9.095 Mutanten und 571 Test-Cases generiert. Ingenieure akzeptierten 73% der vorgeschlagenen Tests.

## 3. Einordnung
- **Vorarbeiten:** Kombiniert LLM-basierte Test-Generierung mit Mutation Testing; nutzt LLM auch für Equivalent-Mutant-Detection
- **Kritisierte/erweiterte Ansätze:** Traditionelle Mutation Testing-Tools generieren zu viele triviale Mutanten; ACH nutzt Klassifizierung und LLM-Guidance für hochrelevante Mutanten
- **Relevanz für Framework-Design:** mittel-hoch — LLM-Integration für Mutant-Klassifizierung und Test-Generierung; Equivalent-Mutant-Detection durch LLM; Praktische Industrie-Validierung

## 4. Technische Inhalte

### Mutationsoperatoren
- Klassifizierung von Mutanten nach Relevanz (z.B. Privacy-relevante vs. triviale)
- Selective Mutation: Nicht alle möglichen Mutanten werden generiert; Fokus auf spezifische Bedenken/Kategorien
- Operator-Level Klassifizierung durch Rules/Heuristics und LLM

### Architektur & Implementierung
- **Ebene:** Source-Code (Kotlin)
- **Komponenten:**
  1. Mutant-Generator (selektiv basierend auf Bedenken)
  2. LLM-basierter Mutant-Klassifizierer
  3. LLM-basierter Test-Generator
  4. LLM-basierter Equivalent-Mutant-Detector

- **LLM-Einsatz:** Multiple LLM-Calls für (1) Mutant-Relevanz-Scoring, (2) Test-Generierung, (3) Äquivalent-Klassfizierung
- **Deployment:** Integration in Meta's Testing-Infrastruktur (Messenger, WhatsApp test-a-thons)

### Kostensenkung & Performance
- Reduktion der Mutanten-Überflutung: Von tausenden möglichen zu ~9k gezielten Mutanten
- Test-Effizienz: 571 Tests für 10.795 Klassen (0.053 Tests pro Klasse durchschnittlich)
- Akzeptanzrate: 73% von LLM-generierten Tests akzeptiert von Ingenieuren

### Equivalent-Mutant-Problem
- **LLM-basierte Equivalent-Mutant-Detection:**
  - Precision: 0.79, Recall: 0.47 (Basis)
  - Mit einfacher Vorverarbeitung: Precision 0.95, Recall 0.96
  - LLM evaluiert Semantic-Äquivalenz zwischen Mutant und Original

- Noch Raum für Verbesserung, aber praktisch verwenden mit Vorverarbeitung möglich

### Skalierbarkeit & Integration
- Deployment auf 7 Meta-Software-Plattformen
- 10.795 Android Kotlin-Klassen
- Integrierbar in bestehende CI/CD und Test-Workflows
- Human-in-the-loop: Ingenieure reviewen und akzeptieren/modifizieren generierte Tests

## 5. Empirische Befunde
- **Testsubjekte/Benchmarks:** 10.795 Android Kotlin-Klassen aus 7 Meta-Plattformen (Messenger, WhatsApp, etc.)
- **Erzeugung:** 9.095 Mutanten, 571 Test-Cases
- **Methodologie:**
  - Gerichtete Mutant-Generierung (z.B. für Privacy-Concerns)
  - LLM-basierte Klassifizierung und Filterung
  - LLM-Test-Generierung mit Mutant-Kontext
  - Engineer-Review und Feedback

- **Zentrale Ergebnisse:**
  - 73% Akzeptanzrate von Ingenieurinnen
  - LLM-Equivalent-Mutant-Detector praktisch nützlich mit Preprocessing (95% Precision, 96% Recall)
  - Positive Feedback from Messenger/WhatsApp test-a-thons
  - Praxis-einsatzbereit in Produktions-Environments

## 6. Design-Implikationen für mein Framework
- **LLM-Integration:** Framework sollte LLM-Plugins unterstützen für (a) Mutant-Relevanz-Scoring, (b) Test-Generierung, (c) Equivalent-Mutant-Detection
- **Selective Mutation:** Klassifikations-Layer für gerichtete Mutant-Generierung (z.B. nach Concerns: Security, Privacy, Performance)
- **Human-in-the-Loop:** Integration von Engineer-Review-Loops und Feedback-Mechanismen in Test-Workflow
- **Equivalent-Mutant-Automation:** LLM-basierter Equivalent-Mutant-Detektor sollte Basis-Komponente sein (mit optionalen Preprocessing-Heuristics)
- **Industrial Validation:** Framework sollte einfache Integration mit bestehenden Test-Frameworks ermöglichen

## 7. Offene Fragen & Limitationen
- **Limitationen:**
  - LLM-Equivalent-Mutant-Detector hat noch hohe False-Positive-Rate (0.21 ohne Preprocessing)
  - Abhängig von LLM-Qualität und -Verfügbarkeit (API-Kosten, Latency)
  - Evaluation auf Android/Kotlin; Transferierbarkeit zu anderen Sprachen unklar
  - Keine Vergleich mit traditionellen automatisierten Äquivalent-Mutant-Detection-Techniken
  - Langfristige Wartbarkeit von LLM-generierten Tests noch nicht untersucht

- **Unbeantwortete Fragen:**
  - Wie robust sind LLM-Tests gegen zukünftige Code-Evoluationen?
  - Welche LLM-Größe/Art ist optimal für verschiedene Concern-Kategorien?
  - Kann man Equivalent-Mutant-Detection besser calibrieren (z.B. mit Fine-Tuning)?
  - Wie skaliert das System bei sehr großen Codebases (Millionen LOC)?
