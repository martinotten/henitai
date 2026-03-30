# Semantic mutation testing

## 1. Metadaten
- **Titel:** Semantic mutation testing
- **Autoren:** John A. Clark, Haitao Dan, Robert M. Hierons
- **Jahr:** 2011
- **Venue:** Science of Computer Programming, Vol. 78, pp. 345-363
- **Paper-Typ:** Empirische Studie + Tool-Paper
- **Sprachen/Plattformen im Fokus:** C, Statecharts (STATEMATE, UML, Stateflow)

## 2. Kernaussage
SMT (Semantic Mutation Testing) ergänzt traditionelles syntaktisches Mutation Testing durch Mutation der Sprachsemantik statt Programmquellcode. Dadurch werden Fehler durch Missverständnisse der Sprachsemantik erfasst (z.B. unterschiedliche Truncation Rules in Z vs. C), nicht nur Tippfehler. SMT generiert weniger Mutanten und kann model-checking für FSM-Spezifikationen nutzen.

## 3. Einordnung
- **Vorarbeiten:** Traditionelles Mutation Testing (syntaktisch), Weak/Firm Mutation, Competent Programmer Hypothesis
- **Kritisierte/erweiterte Ansätze:**
  - Syntaktisches Mutation: Erfasst nur kleine Tippfehler, nicht Sprachverständnis-Fehler
  - Selective Mutation: Reduziert Mutantenzahl, aber nicht Äquivalent-Mutanten-Problem
  - Coupling Hypothesis: Validates FOMs aber nicht alle Szenarien
- **Relevanz für Framework-Design:** mittel — Neuartige Perspektive auf Fehlermodellierung; praktisch eher für spezielle Domänen (Specifications, Statecharts)

## 4. Technische Inhalte

### Mutationsoperatoren
**Semantische Operatoren für C (13 implementiert im SMT-C Tool):**
1. AOR - Assignment in conditional → `==` (häufiger C Fehler)
2. ASD - Remove extra semicolons nach if-Bedingung
3. LBC_I - Add else branch mit trap statement
4. LBM_I - Modify last if to else branch
5. LBC_C - Add default branch zu switch ohne default
6. Weitere ähnliche Operatoren...

**Beispiel-Semantische-Fehler für C:**
- **Division negativ Zahlen:** Z truncates toward -∞, C truncates toward 0
- **Incomplete Branching:** if ohne else vs. if-else
- **Floating-Point Vergleich:** Undefined behavior in C bei FP-Vergleichen

**Statechart-Operatoren:**
- Unterschiedliche Priority Rules zwischen STATEMATE und UML
- Non-determinism handling (STATEMATE vs. Stateflow clockwise rule)

### Architektur & Implementierung
- **SMT-C Tool:**
  - Implementiert in Java, basierend auf Eclipse CDT
  - 3-Layer Architektur: GUI (viewers), Functional Components, Base Layer (TXL, Check)
  - Viewers: Mutant Viewer, Test Viewer, Results Viewer, Console Viewer

- **Implementierungs-Ansätze:**
  1. Parametrisierbar Interpretation (Compiler mit verschiedenen Semantiken)
  2. Rewrite Rules (formale Semantik)
  3. Syntaktische Änderungen zur Simulation semantischer Änderungen (praktisch genutzt)

- **Ansatz 3 Beispiel:** Division-Mutant durch if-else Statement mit Z-Division Helper

### Kostensenkung & Performance
- **Mutantenzahl:** SMT generiert deutlich weniger Mutanten als syntaktische Mutation
  - Eine Semantik-Änderung vs. viele syntaktische Punkte
  - Weniger äquivalente Mutanten
- **Compilation:** Eine Kompilation pro Semantik-Operator (vs. viele für Syntax-Operator)
- **Context-dependent:** Semantische Operatoren sind spezifischer → weniger Mutanten

### Equivalent-Mutant-Problem
- **Weniger Äquivalente:** Weniger Mutanten insgesamt → fewer equivalent mutants
- **Specificity:** Semantische Operatoren sind zielgerichteter, produce fewer false positives
- **Model Checking:** Für FSM/Statecharts kann Equivalence decidable werden (beschränkte Domäne)
- **Komplementär:** SMT und syntaktisches MT sind non-subsuming (neither subsumes other)

### Skalierbarkeit & Integration
- **Prototype Tool:** SMT-C für C; nicht für große Systeme optimiert
- **Domain-Spezifisch:** Sehr effektiv für Spezifikationen/Statecharts, weniger für imperative Programme
- **Language-Dependent:** Operatoren müssen pro Sprache spezifiziert werden

## 5. Empirische Befunde
- **Testsubjekte:**
  - C Code mit semantischen Missverständnissen (Division, Branching, FP-Vergleiche)
  - Statechart Spezifikationen (Cruise-Control Beispiel)
- **Methodologie:**
  - Implementierung semantischer Operatoren im SMT-C Tool
  - Experimentelle Evaluation mit Comparison zu syntaktischen Operatoren
  - Model Checker (CTL Assertions) für FSM Test-Generierung
- **Zentrale Ergebnisse:**
  - SMT generiert weniger Mutanten (4-5x weniger in Beispielen)
  - Keine äquivalenten Mutanten-Subsuming: SMT ⊄ Syntax Mutation, Syntax Mutation ⊄ SMT
  - Unterschiedliche Fehlerklassen erfasst: SMT finds semantic misunderstandings nicht von Syntax MT
  - Model Checking erzeugt direkt Gegenbeispiele als Tests (bei FSM)

## 6. Design-Implikationen für mein Framework
1. **Dual-Mode Mutation:** Framework könnte sowohl syntaktische als auch semantische Mutation unterstützen
2. **Language Semantics:** Framework müsste Sprach-Semantik modellierbar machen (Parameter, rewrite rules)
3. **Context-Awareness:** Semantische Operatoren sollten Code-Context verwenden (z.B. Variable Types)
4. **Specification Support:** First-class Support für FSM/Specification-basierte Mutation
5. **Automatisierte Test-Generierung:** Model Checker Integration für Spezifikationen
6. **Error Model:** Framework sollte verschiedene Fehlertypen (Typos vs. Misunderstandings) unterscheiden

## 7. Offene Fragen & Limitationen
- **Sprach-Abhängigkeit:** Jede Sprache braucht eigene Semantik-Operatoren → aufwändig
- **Semantik-Definition:** Keine Standards für formale Sprachsemantik → oft ad-hoc
- **Tooling:** SMT-C ist Prototype; keine robusten Production Tools
- **Coupling Hypothesis:** Nicht explizit untersucht für semantische Mutation
- **Large Programs:** Scalability zu großen Systemen unklar
- **Operator Completeness:** Nicht klar, ob alle relevanten Semantik-Unterschiede erfasst werden
- **Weak Mutation Vergleich:** Nicht verglichen mit Weak Mutation (ähnliche Effizienzpotenziale)
