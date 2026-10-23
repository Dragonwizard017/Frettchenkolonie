## DevMode.gd
## Feature (v11.10): Entwickler-Modus, aktivierbar über die Einstellungen
## (Passwort-Eingabefeld in PauseMenu.gd, siehe _build_pause_menu() in
## Main.gd) mit dem Passwort "frettchendev". Rein clientseitig - es gibt
## keinen Server/Account, gegen den ein Passwort zu prüfen wäre, daher
## reicht ein einfacher String-Vergleich; das ist kein Sicherheitsfeature,
## sondern nur ein Schutz vor versehentlichem Aktivieren durch normale
## Spieler beim Herumklicken in den Einstellungen.
##
## Andere Systeme fragen `DevMode.enabled` ab, um zusätzliche Test-Buttons/
## -Funktionen einzublenden (siehe z.B. FerretProfilePanel.gd - "Sofort
## legendär machen"-Button). NICHT persistiert (bewusst: soll nach einem
## Neustart nicht automatisch wieder aktiv sein).
extends Node

const PASSWORD := "frettchendev"

signal dev_mode_changed(is_enabled: bool)

var enabled: bool = false

## Gibt true zurück, wenn das Passwort stimmt (und aktiviert den Dev Mode),
## sonst false (Dev Mode bleibt unverändert). Wird vom Passwort-Eingabefeld
## in PauseMenu.gd aufgerufen.
func try_enable(password_input: String) -> bool:
	if password_input == PASSWORD:
		enabled = true
		dev_mode_changed.emit(true)
		return true
	return false

func disable() -> void:
	enabled = false
	dev_mode_changed.emit(false)
