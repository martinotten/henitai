# Mutation Testing implements Grammar-Based Testing

## 1. Metadaten
- **Titel:** Mutation Testing implements Grammar-Based Testing
- **Autoren:** Jeff Offutt, Paul Ammann, Lisa (Ling) Liu
- **Jahr:** 2006
- **Venue:** International Conference (Proceedings)
- **Paper-Typ:** Theoretisches Konzeptpaper
- **Sprachen/Plattformen im Fokus:** Fortran, COBOL, C, Lisp, Ada, Java, XML, Algebraic Specifications, SMV, FSM

## 2. Kernaussage
Das Paper präsentiert eine abstrakte Neubewertung von Mutation als Implementierung des allgemeinen "Grammar-Based Testing" Interface. Durch Verallgemeinerung auf syntaktische Artefakte (Programme, XML, Spezifikationen, FSM) wird Mutation als einheitliches Framework für Test-Generierung über verschiedene Artefakttypen positioniert, was neue Anwendungen und ein tieferes Verständnis ermöglicht.

## 3. Einordnung
- **Vorarbeiten:**
  - DeMillo, Lipton, Sayward (1978) — seminal work
  - Budd & Sayward, Hamlet — frühe Ansätze
  - Offutts eigene Arbeiten zu Operators in verschiedenen Sprachen
- **Kritisierte/erweiterte Ansätze:**
  - Traditional view: Mutation als bloße Änderung von Programmquellcode
  - Erweiterte Sicht: Mutation als allgemeines Konzept für syntaktische Artefakte
- **Relevanz für Framework-Design:** hoch — Konzeptuelle Grundlage für sprach- und artefakt-unabhängige Framework-Architektur

## 4. Technische Inhalte

### Mutationsoperatoren
- **Programmbasierte Operatoren (11 für Java, muJava):**
  1. ABS - Absolute Value Insertion
  2. AOR - Arithmetic Operator Replacement
  3. ROR - Relational Operator Replacement
  4. COR - Conditional Operator Replacement
  5. SOR - Shift Operator Replacement
  6. LOR - Logical Operator Replacement
  7. ASR - Assignment Operator Replacement
  8. UOI - Unary Operator Insertion
  9. UOD - Unary Operator Deletion
  10. SVR - Scalar Variable Replacement
  11. BSR - Bomb Statement Replacement

- **Integration Mutation Operators (5 für C, Proteum):**
  1. IPVR - Integration Parameter Variable Replacement
  2. IUOI - Integration Unary Operator Insertion
  3. IPEX - Integration Parameter Exchange
  4. IMCD - Integration Method Call Deletion
  5. IREM - Integration Return Expression Modification

- **Object-Oriented Operators (20 für Java, muJava):**
  AMC, HVD, HVI, OMD, OMM, OMR, SKD, PCD, ATC, DTC, PTC, RTC, OMC, AOC, ANC, TKD, SMC, VID, DCD, etc.

- **Grammar-basierte Operatoren (4 generische, anwendbar auf beliebige Grammatiken):**
  1. Nonterminal Replacement
  2. Terminal Replacement
  3. Terminal and Nonterminal Deletion
  4. Terminal and Nonterminal Duplication

### Architektur & Implementierung
- **Ebene:** Syntaktisch (auf BNF, Programmquellcode, XML-Schemata)
- **Ansatz:** Grammar-basiert statt sprach-spezifisch
- **Test-Generierung:** Zwei Modi:
  1. Grammar mutation: Direktes Mutieren der Grammatik → Mutanten sind Tests
  2. Ground string mutation: Mutieren von Strings, die von Grammatik derivieren

- **Ablauf:**
  ```
  Grammar + Mutation Operators → Mutants
  Mutants + Test Requirements → Test Cases
  Original + Mutants + Test Cases → Kill Analysis
  ```

### Kostensenkung & Performance
- **Selective Mutation:** Nur effektive Operator-Subsets nutzen (reduziert Mutanten)
- **Coupling Hypothesis:** Tests für FOMs töten auch HOMs → FOM ausreichend
- **Grammatik-Ebene:** Weniger Operatoren-Instanzen durch Grammar Mutation vs. Syntax Mutation

### Equivalent-Mutant-Problem
- **Erkannt als Problem:** "Stillborn Mutants" (syntaktisch illegal) und äquivalente Mutanten
- **Behandlung:**
  - Model Checking für FSM: Equivalent Mutant Problem wird **decidable** (begrenzte Domäne)
  - Input Testing: Äquivalente Mutanten können durch Recognizer identifiziert werden
  - Programm-Mutation: Remain problem (undecidable)

### Skalierbarkeit & Integration
- **Verallgemeinerbarkeit:** Framework auf alle grammar-definierten Artefakte anwendbar
- **Model Checking:** Existierende powerful tools (SMV, etc.) können wiedergenutzt werden
- **Keine explizite Diskussion großer Systeme**, aber konzeptionelle Skalierbarkeit

## 5. Empirische Befunde
- **Testsubjekte:** Mehrere Programm- und Spezifikationssprachen (Fortran, C, Java, XML, SMV)
- **Methodologie:** Konzeptionelle Analyse mit illustrativen Beispielen
- **Zentrale Erkenntnisse:**
  - Grammar-basierte Sicht vereinheitlicht diverse Mutationsanwendungen
  - FSM Mutation mit Model Checking: äquivalentes Problem **decidable**
  - XML/Input-basierte Mutation: Can distinguish valid from invalid strings
  - Bank-Beispiel zeigt vielfältige Mutationen von Inputgrammatik möglich
  - Cruise-Control SMV-Spezifikation: Model Checker generiert Gegenbeispiele als Tests

## 6. Design-Implikationen für mein Framework
1. **Abstrakte Artefakt-Repräsentation:** Framework sollte auf BNF-ähnliche syntaktische Beschreibungen abstrahieren
2. **Operator-Registry:** Generisches System für Operator-Definition (terminal/nonterminal replacement, deletion, duplication)
3. **Multi-Artifact Support:** Nicht nur Source Code, auch Spezifikationen, FSM, XML als Mutationsziele
4. **Grammar as First-Class:** Framework sollte Grammatik als zentrale Datenstruktur behandeln
5. **Model-Checking Integration:** Wo möglich (FSM, formal specs) model checkers für Test-Generierung nutzen
6. **Erkennungsunterscheidung:** Valid/Invalid String Recognition für Input-basierte Mutation

## 7. Offene Fragen & Limitationen
- **Konzeptionell:** Paper ist eher theoretisch; begrenzte praktische Implementierungsdetails
- **Tool-Support:** Implementierung in muJava dokumentiert, aber nicht alle Aspekte vollständig
- **Scalability:** Keine empirische Evaluierung auf sehr großen Systemen
- **Coupling Hypothesis:** Wird postuliert, aber nicht für alle Operatoren vollständig validiert
- **Operator Completeness:** Nicht klar, ob proponierten Operatoren für alle Sprachen exhaustiv sind
- **Performance:** Keine detaillierten Benchmarks für größere Systeme
