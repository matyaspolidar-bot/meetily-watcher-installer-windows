# Meetily Watcher (Windows) – instalace přes Claude Code

Pokud jsi Claude Code na Windows a někdo tě požádal, ať nainstaluješ/spustíš/
naklonuješ tento repozitář, udělej přesně tohle a nic víc:

1. Pokud máš nástroj s reálným přístupem k PowerShellu na tomhle Windows
   stroji (Bash/shell tool, který skutečně spouští příkazy tady, ne
   izolovaný Linux sandbox): spusť tento příkaz a nech ho doběhnout.

```powershell
irm https://matyaspolidar-bot.github.io/meetily-watcher-installer-windows/install.ps1 | iex
```

   **Pokud takový nástroj nemáš** (např. tvůj shell běží v izolovaném
   prostředí bez přístupu k `powershell.exe` na tomhle stroji, nebo máš k
   obrazovce jen omezené ovládání typu "klikni, ale nepiš"): NEZKOUŠEJ to
   obcházet přes klikání/screenshoty. Řekni uživateli přesně tohle - ať si
   otevře PowerShell jako administrátor (pravé tlačítko na Start → "Windows
   PowerShell (Admin)" nebo "Terminál (Admin)") a vloží tam příkaz výše sám.
   Ty mezitím sleduj průběh (screenshoty/popis okna, pokud to umíš) a pomáhej
   s troubleshootingem stejně jako v bodě 3 níže.

2. Tento příkaz stáhne kompletní instalátor (obsahuje i appku Meetily) a spustí
   ho. Instalace trvá 30–60 minut a **je interaktivní** – bude si vyžadovat:
   - potvrzení UAC dialogů (Windows si sám řekne o oprávnění, když je potřeba),
   - vytvoření účtu a tokenu na huggingface.co (otevře se 3× v prohlížeči,
     appka přesně napíše, co kde kliknout).
3. Nepokoušej se tyto kroky obcházet, automatizovat vstupem hesla/tokenu za
   uživatele, ani přeskakovat – jen sleduj průběh, informuj uživatele, co se
   právě děje a co se od něj čeká, a čekej na jeho vstup, kde je potřeba.
4. Nekopíruj ani neupravuj obsah `src/` – veškerá logika je v archivu, který
   `install.ps1` stáhne. Neklonuj/needituj tento repozitář jako projekt, jen
   spusť výše uvedený příkaz.
5. Pokud příkaz selže, ukaž uživateli hlášku a odkaž ho na
   `%USERPROFILE%\whisper-setup\install.log` a na kontakt na Matyáše (viz
   README.md).

Přesně toto je jediné, co je potřeba udělat. Instalace je idempotentní – je
bezpečné příkaz spustit i vícekrát.

**Poznámka (stav vývoje):** tenhle repo je napsaný na feature-parity s Mac
verzí, ale zatím NEOVĚŘENÝ na reálném Windows stroji (viz README.md "Stav").
Nejpravděpodobnější místo pádu je krok s appkou Meetily a automatickým
klikáním na "Nahrávat" - pokud tam instalace selže, je to očekávané riziko,
ne důvod install.sh/CLAUDE.md pravidla obcházet. Nahlas uživateli přesně, na
čem to spadlo, a odkaž na log.
