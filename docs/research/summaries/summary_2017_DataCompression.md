# Speeding-Up Mutation Testing via Data Compression and State Infection

## 1. Metadaten
- **Titel:** Speeding-Up Mutation Testing via Data Compression and State Infection
- **Autoren:** Qianqian Zhu, Annibale Panichella, Andy Zaidman
- **Jahr:** 2017
- **Venue:** PeerJ Preprints (später veröffentlicht)
- **Paper-Typ:** Empirische Studie, Tool-Paper
- **Sprachen/Plattformen im Fokus:** Java

## 2. Kernaussage
Das Paper präsentiert ComMT (Compressed Mutation Testing), ein Verfahren zur Beschleunigung von Mutation Testing durch Datenkompression basierend auf Infection-State-Informationen. Mittels Formal Concept Analysis (FCA) werden ähnliche Mutanten gruppiert und Test-Cases selektiert, um Execution Time um 83,93% zu reduzieren bei nur 0,257% Präzisionsverlust.

## 3. Einordnung
- **Vorarbeiten:** Basiert auf Infection-Based Optimisation (Just et al.), Mutant Clustering (Hussain), Test Prioritization
- **Kritisierte/erweiterte Ansätze:** Kombiniert Infection-Information mit bidirektionalem Mutant-Test-Clustering mittels FCA
- **Relevanz für Framework-Design:** Hoch — praktische, elegante Methode zur Kostenreduktion ohne vollständige Mutant-Ausführung

## 4. Technische Inhalte

### Mutationsoperatoren
Nicht primär; verwendet EvoSuite's interne Mutation Engine für Java.

### Architektur & Implementierung
- **Ebene:** AST/Bytecode (EvoSuite-basiert)
- **Prozess:** 5-stufiger Prozess: Instrumentation → Test Execution → Infection Analysis → FCA → Datenkompression

**Detaillierter Ablauf:**

1. **Instrumentation:** Mutants mit EvoSuite generieren, Programm für Infection-Tracking instrumentieren
2. **Test Execution:** Test-Suite auf instrumentiertem Original-Programm ausführen; Infection-Daten sammeln
3. **Infection Analysis:** Mutant-by-Test Infection Matrix (m×n, binär) erstellen
4. **Formal Concept Analysis (FCA):** FCA auf Infection Matrix anwenden → formale Concepts extrahieren
5. **Datenkompression:** Maximal Groupings aus Lattice selektieren → Rows/Columns komprimieren

**FCA-Konzept:** Gruppiert Mutanten in formale Concepts basierend auf gemeinsamen Infection-Patterns. Maximal Groupings sind direkt mit Lattice-Exit verbunden.

### Kostensenkung & Performance
**Test Case Selection Strategien:**

1. **FCA-Based Selection:** Ein Test pro Concept; behandelt Concepts gleichberechtigt
2. **Set Cover Greedy:** Wählt Tests, die maximale Anzahl ungecoverter Groupings abdecken (NP-hard Problem)
3. **Sorting by Maximal Groupings:** Tests nach Anzahl Groupings-Mitgliedschaften sortieren

**Ergebnisse:**
- Durchschnittlich 8,48 Mutanten pro Maximal Grouping → 88,2% Compression-Ratio
- ComMT ohne Test-Selection: 83,93% Execution-Time-Reduktion bei 0,257% Error Rate
- Set Cover: 89,82% Reduktion aber -19,36% Präzisionsverlust
- FCA-Based: 86,84% Reduktion bei -4,76% Verlust
- Sorting-Based: 84,51% Reduktion bei 0,262% Verlust

### Equivalent-Mutant-Problem
FCA-Gruppierung berücksichtigt indirekt Äquivalenz; Mutanten mit identischem Infection-Muster sind potentiell ähnlich im Strong-Mutation-Outcome. Allerdings: keine explizite Äquivalenz-Erkennung, nur Approximation durch Infection-Ähnlichkeit.

### Skalierbarkeit & Integration
- **Evaluierung:** 6 Open-Source-Java-Projekte (SF110)
- **Größen:** 2K-61K LOC, 43-596 Klassen, 84-4699 Tests, 302-49925 Mutanten
- **Constraint:** Compression ist schnell (< 10 Sekunden)
- **Flaschenhals:** Test-Suite-Größe beeinflusst FCA-Clustering-Genauigkeit; kleine Suites → höhere Error Rates

## 5. Empirische Befunde
- **Testsubjekte/Benchmarks:** jsecurity, summa, db-everywhere, noen, jtailgui, caloriecount
- **Methodik:** EvoSuite-generierte Tests mit Strong-Mutation-Kriterium; Infection-Data-Collection; ConExp für FCA
- **Zentrale Ergebnisse:**
  - **RQ1:** FCA findet maximal Groupings mit durchschnittlich 8,48 Mutanten
  - **RQ2:** Mutanten-Ähnlichkeit sehr hoch (Error Rate ~0%); aber hohe Varianz zwischen Projekten (-33% bis +40%)
  - **RQ3:** FCA-Based Test-Selection reduziert Test-Count um durchschnittlich 44,03%
  - **RQ4:** ComMT ermöglicht 83,93%-84,51% Execution-Time-Reduktion mit minimalen Präzisions-Verlusten
  - **Größe der Test-Suite ist kritisch:** Kleine Suites haben niedrigere Clustering-Genauigkeit

## 6. Design-Implikationen für mein Framework
- **FCA-Integration:** FCA als optionale Kompressions-Engine implementieren
- **Infection-Tracking:** Schwache Mutation als Vorauswahl; Strong-Mutation für finale Bewertung
- **Bidirektionales Clustering:** Nicht nur Mutanten gruppieren, sondern auch Tests; Trade-off zwischen Coverage und Speed
- **Test-Auswahl:** Mehrere Strategien anbieten (FCA-based, Greedy Set-Cover, Sorting); konfigurierbar
- **Threshold-Management:** Schwellwerte für Infection-Ähnlichkeit definieren und tunen
- **Quality-Score:** Pro-Mutant-Gruppe Quality-Metriken berechnen
- **Adaptive Auswahl:** Framework sollte erkennen, wenn Test-Suite zu klein ist (und FCA deaktivieren oder warnen)

## 7. Offene Fragen & Limitationen
- **Generalisierung auf manuelle Tests:** Evaluierung nur auf Auto-Generated Tests (EvoSuite); Verhalten bei realen, manuellen Test-Suites unklar
- **Andere Mutation-Tools:** Results basieren auf EvoSuite's Mutation Engine; Übertragbarkeit auf Major, PIT unklar
- **Clustering-Genauigkeit:** Abhängigkeit von Test-Suite-Größe ist praktisches Hindernis; kleine Projekte könnten leiden
- **FCA-Overhead:** Rechenzeit für FCA-Processing nicht gegenüber Einsparungen verglichen
- **Infection-Definition:** Weak Mutation als Proxy; nicht immer exakt für Strong Mutation
- **Equivalence-Handling:** FCA erkennt Äquivalenz nicht explizit; nur Infection-Patterns
