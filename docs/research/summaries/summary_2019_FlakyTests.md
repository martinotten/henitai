# Mitigating the Effects of Flaky Tests on Mutation Testing

## 1. Metadaten
- **Titel:** Mitigating the Effects of Flaky Tests on Mutation Testing
- **Autoren:** August Shi, Jonathan Bell, Darko Marinov
- **Jahr:** 2019
- **Venue:** ISSTA '19 (ACM International Symposium on Software Testing and Analysis)
- **Paper-Typ:** Empirische Studie + Tool-Paper
- **Sprachen/Plattformen im Fokus:** Java, PIT Mutation Testing Tool

## 2. Kernaussage
Das Paper zeigt, dass flaky Tests die Zuverlässigkeit von Mutation Testing gefährden, da Testergebnisse nicht-deterministisch sein können. Die Autoren proposieren Techniken zur Flaky-Test-Mitigation durch strategische Wiederholungen, Testausführung und -priorisierung, implementiert im Tool PIT.

## 3. Einordnung
- **Vorarbeiten:** Basiert auf etabliertem Mutation-Testing-Rahmen (DeMillo et al.); erweitert Forschung zu flaky Tests (hauptsächlich im Kontext Regression Testing)
- **Kritisierte/erweiterte Ansätze:** Traditionelle Mutation Testing ignorierten nicht-deterministische Coverage und flaky Test-Outcome; neuer Ansatz verfolgt "unknown" Mutanten
- **Relevanz für Framework-Design:** **mittel** — Das Papier adressiert ein praktisches Problem, das jedes Mutation-Testing-Framework berücksichtigen sollte; weniger relevant für die Mutationsoperator-Definition, aber wichtig für Ausführungslogik und Zuverlässigkeit.

## 4. Technische Inhalte

### Mutationsoperatoren
Nicht explizit thematisiert. Das Papier konzentriert sich auf die Zuverlässigkeit von Mutation Testing bei Vorhandensein flaky Tests, nicht auf spezifische Operatoren.

### Architektur & Implementierung
- **Ebene:** Bytecode-Level (modifiziert PIT auf Bytecode-Instrumentation-Ebene)
- **Tool:** Modifizierte Version von PIT (PiTest), Java-basiert
- **Algorithmen:**
  1. **Coverage Collection:** 16-fache Wiederholung der Tests, Union aller abgedeckten Blöcke als Eingabe für Mutant-Generierung
  2. **Testausführung:** Instrumentation zur Verfolgung, ob mutierter Bytecode tatsächlich ausgeführt wird
  3. **Kategorisierung:** Einführung der Kategorie "unknown" für Mutant-Test-Paare, bei denen Coverage nicht garantiert ist

### Kostensenkung & Performance
- **Strategische Wiederholungen:** Bis zu 16 Wiederholungen bei Coverage-Collection und Mutant-Execution (konfigurierbar)
- **Test-Priorisierung:** Tests werden nach Ausführungszeit und Coverage-Häufigkeit priorisiert
- **Isolation:** Mehrere Isolationsstrategien untersucht: Standard (keine Isolation), Isolation pro JVM, Isolation pro Mutant-Test-Paar
- **Performance-Trade-off:** Default-Modus ohne Isolation/Wiederholung als praktischer Kompromiss; maximale Zuverlässigkeit durch Isolation und Wiederholung mit erheblichem Overhead

### Equivalent-Mutant-Problem
Nicht explizit thematisiert.

### Skalierbarkeit & Integration
- **Große Codebases:** Evaluation auf 30 Open-Source-Java-Projekten verschiedener Größen
- **CI/CD:** Nicht explizit thematisiert
- **Implementierung:** Direkt in PIT integriert, öffentlich verfügbar mit Dataset

## 5. Empirische Befunde
- **Testsubjekte/Benchmarks:** 30 Open-Source-Java-Projekte (Apache Commons, Dropwizard, etc.)
- **Methodik:**
  - RQ1: Flakiness in Coverage-Daten (16 Wiederholungen, Coverage-Variabilität gemessen)
  - RQ2-RQ4: Vergleich verschiedener Konfigurationen (Coverage-Collection, Mutation-Execution, Priorisierung)

- **Zentrale Ergebnisse:**
  1. **Coverage Non-Determinismus:** 22% der Statements zeigen nicht-deterministische Coverage; 74% bei cloudera.oryx
  2. **Mutant-Status Unsicherheit:** Ohne Mitigation: 2.866 Mutanten mit "unknown"-Status; 9% aller Mutant-Test-Paare unknown
  3. **Mutations-Score-Varianz:** Mutation Scores schwanken durchschnittlich um 4 Prozentpunkte zwischen Ausführungen
  4. **Effektivität der Mitigation:** 79,4% Reduktion der "unknown" Mutanten durch vorgeschlagene Techniken
  5. **Coverage-Collection:** Default-Modus ohne Isolation/Wiederholung als praktischer Trade-off; statistisch signifikanter Unterschied bei mutant-test Paaren (p<0.01), aber nicht bei absoluten Mutanten (p=0.078)

## 6. Design-Implikationen für mein Framework
1. **Flaky-Test-Handling obligatorisch:** Framework sollte Mechanismen zur Flaky-Test-Erkennung und -Mitigation integrieren, nicht nur als Optional
2. **Konfigurierbare Wiederholungen:** Coverage Collection und Mutant Execution sollten wiederholbar sein mit einstellbaren Schwellwerten
3. **Coverage-Tracking:** Explizite Verfolgung, ob mutierter Code tatsächlich ausgeführt wird (nicht nur statische Coverage-Analyse)
4. **"Unknown"-Status:** Einführung einer dritten Kategorie (neben killed/survived) für ambiguous Mutanten
5. **Testausführungs-Isolation:** Verschiedene Isolationsstufen sollten verfügbar sein; mindestens Isolation zwischen Mutanten erwägen
6. **Performance-Sensibilität:** Framework sollte transparente Optionen bieten zwischen Zuverlässigkeit und Performance; Default sollte praktikabel sein

## 7. Offene Fragen & Limitationen
- **Limitationen:**
  - Fokus auf Java/PIT; Generalisierbarkeit zu anderen Sprachen/Tools unklar
  - 16 Wiederholungen als "empirischer Wert" gewählt; keine theoretische Begründung
  - Fokus auf Outcome-Flakiness von Coverage, nicht auf Outcome-Flakiness von Testergebnissen selbst (separate Problematik)

- **Unbeantwortete Fragen:**
  - Optimalzahl der Wiederholungen für verschiedene Projekt-Charakteristiken?
  - Kosten-Nutzen-Analyse detaillierter durcharbeiten (Trade-off zwischen 79,4% Reduktion und Performance-Overhead)?
  - Verhältnis zwischen Test-Order-Dependencies und Mutant-Order-Dependencies weiter untersuchen?
