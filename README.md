
World-of-Warcraft-Addon mit einem eigenen Fenster, um Items schnell zwischen Inventar und Bank zu verschieben – einzeln oder als ganze Kategorie. Die Blizzard-Fenster bleiben unverändert.

## Installation

1. Repository herunterladen (oder `git clone`).
2. Den Ordner `QuickBank` nach `World of Warcraft/_retail_/Interface/AddOns/` kopieren.
   Der Ordner muss `QuickBank` heißen und direkt `QuickBank.toc` enthalten.
3. Spiel starten bzw. `/reload` und das Addon in der Addon-Liste aktivieren.

## Nutzung

Beim Öffnen der Bank erscheint das QuickBank-Fenster automatisch: links die Bank, rechts das Inventar, jeweils nach Kategorien gruppiert.

- **Shift-Linksklick** oder **Rechtsklick** auf ein Item: Item auf die andere Seite verschieben
- **„Alle >> Bank“ / „Alle >> Inventar“**: die ganze Kategorie verschieben
- **Suche**: filtert beide Seiten nach Item-Namen; „Treffer >>“ verschiebt alle Treffer
- Beim Verschieben werden vorhandene Teilstapel automatisch aufgefüllt
- Fenster per Drag verschieben, **ESC** schließt es

### Regeln

Über **„Regeln“** (oder `/qb regeln`) legst du eigene Regeln an: Name, Richtung (Bank / Inventar) und beliebige Item-Typen.
**„Aufräumen“** wendet alle aktiven Regeln auf einmal an, einzelne Regeln lassen sich auch direkt ausführen.

### Befehle

| Befehl | Funktion |
|---|---|
| `/qb` oder `/quickbank` | Fenster ein-/ausblenden |
| `/qb auto` | Automatisches Öffnen an der Bank an/aus |
| `/qb regeln` | Regel-Fenster öffnen |
| `/qb reset` | Fensterposition zurücksetzen |
