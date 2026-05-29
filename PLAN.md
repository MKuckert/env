# Project Plan: Benchmark-Auswertung und TPS-Vergleichsplot

## 🎯 Objective

Ein Python-Skript soll alle CSV-Benchmarkdateien unter einem angegebenen Wurzelverzeichnis wiederholt auswerten, unvollständige oder fehlerhafte Benchmarks erkennbar machen und einen Vergleichsplot der Token-pro-Sekunde-Metriken für aktuelle und zukünftige Läufe erzeugen.

## 🛠 Requirements & Decisions

- **Frameworks:** Bestehende Benchmark-Erzeugung per Bash-Skript mit `uvx llama-benchy`; neue lokale Auswertung als eigenständiges Python-Skript im `llama-benchy`-Verzeichnis
- **Chosen Libraries:** `pandas`, `matplotlib`
- **Error Handling Strategy:** Das Skript durchsucht das referenzierte Wurzelverzeichnis rekursiv nach allen `.csv`-Dateien und verarbeitet jede gefundene Datei. Kaputte CSV-Dateien und fehlende Pflichtspalten werden moniert. Fehlende erwartete Tests und unvollständige Benchmarks werden als Warnung gemeldet, vorhandene Daten aber trotzdem verarbeitet. Zusätzliche CSV-Dateien, zusätzliche Spalten und zusätzliche `test_name`-Werte bleiben erlaubt. Unfaire Messregime werden unverändert verarbeitet und nicht speziell gefiltert. Fehlende numerische Werte bleiben intern `NaN`/leer für Aggregation und Plot; in menschenlesbarer Ausgabe werden sie als `nicht vorhanden` markiert.

## 🏗 Implementation Steps

> Status Markers: [ ] Open, [/] In Progress, [x] Completed (after review by the Reviewer only!)

- [x] **Task 1: Analyse-Skript und CLI-Struktur anlegen**
  - **Description:** Ein Python-Skript im `llama-benchy`-Verzeichnis anlegen, das ein Wurzelverzeichnis als Eingabe akzeptiert, dieses rekursiv nach `.csv`-Dateien durchsucht und eine reproduzierbare Ausführung für zukünftige Läufe ermöglicht.
  - **Review Criteria:** Das Skript lässt sich lokal mit Python starten, akzeptiert mindestens einen Verzeichnispfad als Eingabe, scannt das referenzierte Verzeichnis rekursiv und berücksichtigt alle darin gefundenen CSV-Dateien.
- [x] **Task 2: CSV-Validierung und Normalisierung implementieren**
  - **Description:** Pflichtspalten für die TPS-Auswertung (`model`, `test_name`, `t_s_mean`, `t_s_std`, `t_s_req_mean`, `t_s_req_std`, `peak_ts_mean`, `peak_ts_std`, `peak_ts_req_mean`, `peak_ts_req_std`) prüfen, kaputte CSV-Dateien sauber melden, optionale Zusatzspalten wie Latenzwerte tolerieren, Metadaten wie Quelle/Dateiname/Engine/Modell/Test extrahieren und Datensätze in ein einheitliches Tabellenformat überführen.
  - **Review Criteria:** Fehlende Pflichtspalten und nicht lesbare CSV-Dateien werden eindeutig gemeldet; zusätzliche Spalten bleiben erlaubt, ohne die Verarbeitung zu brechen.
- [ ] **Task 3: Erwartete Tests und Vollständigkeitsprüfung ergänzen**
  - **Description:** Die aktuell erwarteten `test_name`-Werte aus dem Benchmark-Setup explizit hinterlegen: `pp2048`, `tg32`, `tg1024`, `ctx_pp @ d1024`, `ctx_tg @ d1024`, `pp2048 @ d1024`, `tg32 @ d1024`, `tg1024 @ d1024`, `ctx_pp @ d2048`, `ctx_tg @ d2048`, `pp2048 @ d2048`, `tg32 @ d2048`, `tg1024 @ d2048`. Vollständigkeit pro CSV als Präsenzprüfung definieren: Jeder erwartete Testname muss mindestens einmal in der Datei vorkommen; Duplikate bleiben erlaubt und werden nicht als Fehler gewertet. Fehlende erwartete Tests warnend ausgeben und zusätzliche Tests tolerieren.
  - **Review Criteria:** Fehlende erwartete Tests erscheinen als Warnung; zusätzliche Tests lösen keine Warnung aus; Vollständigkeit wird als mindestens eine gefundene Zeile pro erwarteten Testname geprüft; unvollständige Benchmarks bleiben in Bericht und Plot nachvollziehbar.
- [ ] **Task 4: Aggregierte TPS-Vergleichsdaten erzeugen**
  - **Description:** Alle vorhandenen Läufe im Zielverzeichnis zusammenführen, mehrfache Läufe derselben Engine/Modell/Test-Kombination deterministisch per arithmetischem Mittel über die vorhandenen CSV-Zeilen aggregieren und dabei für jede numerische TPS-Kennzahl (`t_s_mean`, `t_s_std`, `t_s_req_mean`, `t_s_req_std`, `peak_ts_mean`, `peak_ts_std`, `peak_ts_req_mean`, `peak_ts_req_std`) den Mittelwert über alle vorhandenen Werte bilden. Fehlende Werte bleiben intern numerisch leer und werden in der menschenlesbaren Ausgabe als `nicht vorhanden` dargestellt.
  - **Review Criteria:** Mehrere Läufe im selben Verzeichnis werden gemeinsam ausgewertet; neue Engines und Modelle erscheinen automatisch; die Aggregationsregel ist eindeutig dokumentiert und reproduzierbar; fehlende Werte werden in Berichten konsistent als `nicht vorhanden` ausgewiesen, ohne die numerische Verarbeitung oder den Plot zu brechen.
- [ ] **Task 5: TPS-Vergleichsplot erstellen**
  - **Description:** Einen Plot erzeugen, der Token-pro-Sekunde-Vergleiche zwischen Engines/Modellen für die vorhandenen Tests visualisiert, fehlende Daten klar erkennbar macht und nur TPS-Metriken darstellt. Fehlende Werte werden im Plot nicht als Balken gezeichnet; stattdessen erscheint an der entsprechenden Position eine sichtbare Kennzeichnung wie `n/v` oder eine gleichwertige Markierung in der Grafik oder Legende.
  - **Review Criteria:** Der Plot wird als Datei gespeichert, vergleicht die TPS-Metriken verständlich, bleibt auch bei zusätzlichen Engines oder unvollständigen Testmengen lesbar, enthält keine obligatorische Latenzvisualisierung und macht fehlende TPS-Werte visuell explizit.
- [ ] **Task 6: Konsolenbericht, Verifikation und Nutzungsdokumentation ergänzen**
  - **Description:** Eine textuelle Zusammenfassung mit Warnungen zu kaputten Dateien, fehlenden Pflichtspalten, fehlenden erwarteten Tests und optionalen Ausreißer-Hinweisen ausgeben, die Nutzung des Skripts kurz dokumentieren und Verifikationsschritte mit dem aktuellen Benchmark-Korpus sowie synthetischen Fehlerszenarien beschreiben.
  - **Review Criteria:** Die Ausgabe ist für wiederholte Nutzung verständlich; Fehler, Warnungen und erzeugte Artefakte sind schnell auffindbar; die Verifikation umfasst mindestens den aktuellen Benchmark-Bestand, eine kaputte CSV, eine CSV mit fehlender Pflichtspalte, eine unvollständige Benchmark-CSV und eine CSV mit zusätzlichen `test_name`-Werten.

## 🛡 Edge Case & Safety Checklist

- [ ] Alle CSV-Dateien im referenzierten Wurzelverzeichnis werden rekursiv berücksichtigt
- [ ] Kaputte CSV-Dateien werden moniert
- [ ] Fehlende Pflichtspalten werden als Fehler behandelt
- [ ] Zusätzliche Spalten werden toleriert
- [ ] Fehlende erwartete `test_name`-Werte werden gewarnt
- [ ] Zusätzliche `test_name`-Werte werden toleriert
- [ ] Mehrere Läufe am selben Tag und im selben Verzeichnis werden gemeinsam verarbeitet
- [ ] Neue Engines und Modelle werden automatisch übernommen
- [ ] Unvollständige Benchmarks werden gewarnt, aber vorhandene Daten weiter verarbeitet
- [ ] Fehlende Werte werden intern numerisch leer gehalten, in menschenlesbarer Ausgabe als `nicht vorhanden` markiert und im Plot sichtbar gekennzeichnet
- [ ] Ausreißer werden höchstens als Hinweis erwähnt
- [ ] Keine getrennte Bewertung unfairer Messregime im Skript
- [ ] Kein Vergleich mit Inhalten anderer Ordner außerhalb des referenzierten Wurzelverzeichnisses

## 📝 Review Log (Mode 1: Plan Review)

- **Round 1:** Not approved. Gaps: (1) Directory scan behavior is ambiguous; the script must scan the input directory recursively for `*.csv`, because the current layout stores files under dated `raw/` subdirectories. (2) The expected benchmark matrix is not specified concretely enough; derive and document the exact expected `test_name` set from `bench-qwen3.6-27B-all.sh` for the current setup, including how repeated `pp2048` / cached-context rows are counted for completeness checks. (3) `nicht vorhanden` handling is underspecified; define where this literal appears (console/table/export) and how missing numeric values are represented in the TPS plot without poisoning numeric processing. (4) The plan drifts out of scope by aggregating latency metrics; the requested plot scope is TPS comparison only, so latency should be optional text output at most or removed from scope. (5) Test coverage is missing; add concrete verification steps based on the current benchmark corpus plus synthetic malformed/missing-column CSV fixtures.
- **Round 2:** Not approved. Follow-up gaps: (1) Limit mandatory CSV validation to TPS-relevant columns instead of coupling to latency-only fields. (2) Define the deterministic aggregation rule for repeated engine/model/test combinations. (3) Specify the visual rendering rule for missing TPS values in the plot. (4) Clarify completeness as at-least-once presence per expected test name.
- **Round 3:** Approved

## 🚦 Final Status (Mode 2: Code Review)

- Not started
