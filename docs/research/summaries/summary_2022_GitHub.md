# Mutation testing in the wild: findings from GitHub

## 1. Metadaten
- **Titel:** Mutation testing in the wild: findings from GitHub
- **Autoren:** Ana B. Sánchez, Pedro Delgado-Pérez, Inmaculada Medina-Bulo, Sergio Segura
- **Jahr:** 2022
- **Venue:** Empirical Software Engineering (Springer)
- **Paper-Typ:** Mining Study / Empirische Studie
- **Sprachen/Plattformen im Fokus:** Alle Programmiersprachen (Java, C/C++, Python, PHP, JavaScript, Go, Ruby, C#, etc.)

## 2. Kernaussage
Das Paper präsentiert eine umfangreiche Mining-Studie der Mutation-Testing-Adoption auf GitHub. Es identifiziert 127 Mutation-Testing-Tools und analysiert über 3.5K aktive GitHub-Repositories. Zentrale Erkenntnisse: Infection (PHP), PIT (Java) und Humbug (PHP) dominieren praktische Nutzung; großer Gap zwischen akademischen Tools (Java/C++) und praktisch verwendeten Tools (PHP, JavaScript).

## 3. Einordnung
- **Vorarbeiten:** Baut auf früheren Surveys (Papadakis et al. 2019, Jia & Harman 2011) auf; erweitert auf aktuelle Tools und GitHub-Mining
- **Kritisierte/erweiterte Ansätze:** Bisherige Surveys fokussierten auf Forschung; praktische Adoption großtenteils unbekannt
- **Relevanz für Framework-Design:** **hoch** — Zeigt welche Tools praktisch erfolgreich sind und wo Gaps in Forschung vs. Praxis existieren; wichtig für Feature-Priorisierung und Design-Entscheidungen.

## 4. Technische Inhalte

### Mutationsoperatoren
Nicht Fokus des Papers; beschreibt Tool-Landschaft statt Operatoren.

### Architektur & Implementierung
**Tool-Integration-Methoden in Projekten:**
- Executable Files (z.B., .jar, .phar)
- Dependency Management (Maven, Gradle, Composer, RubyGems)
- Build-Tool Integration (Bazel, Sbt, Ivy)
- IDE Plugins
- Configuration Files (pom.xml, build.gradle, infection.json, stryker.conf, etc.)

**Mining-Methodik:**
- Web Scraping mit HtmlUnit
- GitHub GraphQL API
- Manual Review & Classification (3.581 aktive Repositories)

### Kostensenkung & Performance
Nicht Fokus; Tools werden nach Popularität & Adoption analysiert, nicht Performance.

### Equivalent-Mutant-Problem
Nicht adressiert in diesem Paper.

### Skalierbarkeit & Integration
- **Tool Proliferation:** 127 Mutations-Tools identifiziert (87 aus Papadakis 2019 + 31 neue + 9 aus GitHub)
- **Adoption Scale:** 6.633 Repositories initial gefunden; 3.581 aktive Repositories nach Filtering
- **Tool Coverage:** 55 von 127 Tools mit ausreichend Information für GitHub-Search
- **Top 10 Tools:** 3.581 aktive Repositories auf top 10 Tools konzentriert

## 5. Empirische Befunde
- **Testsubjekte/Benchmarks:**
  - 127 Mutations-Tools (Releases 2001-2021)
  - 6.633 GitHub Repositories (initial)
  - 3.644 aktive Repositories (mit Commits letzte 12 Monate)
  - 3.581 Repositories nach manualer Verifizierung
  - Manual Review aller 3.581 Repositories

- **Methodik:**
  - RQ1: Systematic Tool Compilation (Literature + GitHub)
  - RQ2: GitHub Mining (automated search + API)
  - RQ3: Manual Classification (teaching, research, development, extension)
  - RQ4: Popularity Analysis (commits, contributors, stars, forks, watchers)

- **Zentrale Ergebnisse:**

  1. **RQ1 - Tool Support:**
     - 127 Tools total
     - Wachstum über Zeit: 5-13 Tools/Jahr (2008-2020)
     - Peak 2017-2019
     - Dominated by Java (16%), C/C++ (14%), Models/Specs (10%)
     - Emerging: JavaScript, Python, Swift, Solidity

  2. **RQ2 - Adoption:**
     - Top Tools by GitHub usage:
       1. Infection (PHP): 1.213 active repos
       2. PIT (Java): 816 active repos
       3. Humbug (PHP): 636 active repos
       4. StrykerJS (JavaScript): 487 active repos
       5. Mutant (Ruby): 296 active repos
     - Significant adoption growth in recent years
     - 7 of 10 most-starred tools NOT in literature

  3. **RQ3 - Project Types:**
     - 21% Industry
     - 6.8% Academia
     - 3.4% Public Institutions
     - Predominant use: Development (majority)
     - Secondary: Teaching & Learning
     - Tertiary: Research

  4. **RQ4 - Activity & Relevance:**
     - Active projects: consistent commits
     - Popular projects: Infection/PIT repos have hundreds of stars/forks
     - Gap visible: Academic tools (Java/C++) less used in GitHub vs. practice-oriented tools (PHP/JavaScript/Python)

  5. **Research-Practice Gap:**
     - Literature focused on: Java, C/C++, UML
     - GitHub focused on: PHP, JavaScript, Python
     - 7 of 10 top tools absent from literature
     - Suggests academic research disconnected from practical needs

## 6. Design-Implikationen für mein Framework
1. **Multi-Language Support ist kritisch:** Framework muss nicht nur Java/C++ unterstützen, sondern auch PHP, JavaScript, Python, Go, Ruby
2. **Praktische Integration im Fokus:** Framework-Design sollte einfache Integration via Build-Tools, Dependency Management priorisieren
3. **Developer Usability > Research Rigor:** Tools, die praktisch erfolgreich sind, priorisieren Usability über akademische Vollständigkeit
4. **Emerging Languages:** Framework sollte evolutionär neue Sprachen/Domänen (Solidity, Swift) unterstützen können
5. **Configuration-first Approach:** JSON/YAML basierte Konfiguration (wie Infection, Stryker) scheint praktisch erfolgreich
6. **CI/CD Integration:** Erfolgreiche Tools integrieren mit Maven, Gradle, etc.; Framework sollte damit früh vorsehen
7. **Avoid Toolkit-Fragmentation:** Viele namenlose Prototypen (35% der Tools); Framework sollte klare Identität & Maintenance haben

## 7. Offene Fragen & Limitationen
- **Limitationen:**
  - GitHub-Mining limited zu Repositories mit letztem Commit in 12 Monaten (keine historische Analyse)
  - Quantitative Data (commits, stars) ≠ tatsächliche Nutzungsintensität
  - Nur Repositories mit evidenten Tool-References berücksichtigt; mögliche Nutzung ohne explicit reference missed
  - Manual Classification auf 3.581 Repos ist Mensch-intensiv; Replikation aufwändig
  - False Positives filtert manuell

- **Unbeantwortete Fragen:**
  - Warum sind praktisch erfolgreiche Tools (Infection, Humbug, StrykerJS) in Literatur unterrepräsentiert?
  - Wie könnte Forschung Research-Practice-Gap schließen?
  - Werden Mutations-Tools tatsächlich aktiv genutzt oder sind sie nur als Dependencies vorhanden?
  - Welche Feature/Capabilities sind am wichtigsten für praktizierende Entwickler?
  - Wie sieht Adoption innerhalb Industrie aus (nicht nur auf GitHub)?
