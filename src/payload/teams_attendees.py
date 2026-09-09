"""Nepovinne napojeni na firemni kalendar (Microsoft Graph) - zjisti, kdo
byl pozvany na schuzku prekryvajici se s casem nahravky, at se pri
vyplnovani jmen mluvcich (_speakers.json) neveslo jmeno z hlavy, ale da se
vybrat ze skutecneho seznamu ucastniku.

DULEZITE: tohle NEPOZNA, kdo z ucastniku prave mluvi (diarizace zustava
SPEAKER_00/01/...) - jen ukaze, kdo na schuzce vubec byl. Prirazeni
konkretniho jmena ke konkretnimu mluvcimu je porad rucni krok
(apply_speaker_names.py).

Bez vyplnene konfigurace (teams_config.json) se cele proste preskoci -
nic se nerozbije, dokud IT neschvali pristup k Microsoft Graph. Az bude
potreba, staci poslat IT/administratorovi presne tohle (jednorazovy
pozadavek, zadne dalsi obtezovani):

  1. Azure Portal -> Azure Active Directory -> App registrations -> New registration
     (staci nazev, napr. "Meetily Watcher - kalendar").
  2. API permissions -> Add a permission -> Microsoft Graph -> Application permissions
     -> Calendars -> Calendars.Read -> Add permissions -> Grant admin consent.
  3. Certificates & secrets -> New client secret -> zkopirovat hodnotu (jen jednou vidatelna).
  4. Predat: Tenant ID, Application (client) ID, client secret hodnotu.

Tyhle tri hodnoty se vyplni do %USERPROFILE%\\whisper-setup\\teams_config.json
(viz teams_config.example.json ve stejne slozce jako tenhle soubor).
"""
import json
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

CONFIG_PATH = Path(__file__).resolve().parent / "teams_config.json"
GRAPH_BASE = "https://graph.microsoft.com/v1.0"
LOOKAROUND_MINUTES = 15  # jak daleko pred/po nahravce hledat prekryvajici se kalendarovou udalost


def _load_config() -> dict | None:
    if not CONFIG_PATH.exists():
        return None
    try:
        cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None
    if not all(cfg.get(k) for k in ("tenant_id", "client_id", "client_secret")):
        return None
    return cfg


def _current_user_upn(cfg: dict) -> str | None:
    """Kalendar konkretniho konzultanta - bud rucne prepsany v configu
    (calendar_user), nebo odvozeny z prihlaseneho Windows uctu (funguje na
    AD-joined strojich, kde UPN odpovida M365 e-mailu)."""
    if cfg.get("calendar_user"):
        return cfg["calendar_user"]
    try:
        result = subprocess.run(
            ["whoami", "/upn"], capture_output=True, text=True, timeout=5,
        )
        return result.stdout.strip() or None
    except (OSError, subprocess.TimeoutExpired):
        return None


def _get_access_token(cfg: dict) -> str | None:
    try:
        import msal
    except ImportError:
        return None
    app = msal.ConfidentialClientApplication(
        cfg["client_id"],
        authority=f"https://login.microsoftonline.com/{cfg['tenant_id']}",
        client_credential=cfg["client_secret"],
    )
    result = app.acquire_token_for_client(scopes=["https://graph.microsoft.com/.default"])
    return result.get("access_token")


def get_meeting_attendees(created_at_iso: str, duration_seconds: float) -> list[str]:
    """Jmena pozvanych na kalendarovou udalost prekryvajici se s casem
    nahravky. Vraci prazdny seznam pri jakekoliv chybe nebo chybejici
    konfiguraci - tohle je jen pomocna vec, nikdy nesmi shodit zpracovani
    nahravky."""
    cfg = _load_config()
    if not cfg:
        return []
    upn = _current_user_upn(cfg)
    if not upn:
        return []
    token = _get_access_token(cfg)
    if not token:
        return []

    try:
        import requests
    except ImportError:
        return []

    created_at = datetime.fromisoformat(created_at_iso)
    window_start = created_at - timedelta(minutes=LOOKAROUND_MINUTES)
    window_end = created_at + timedelta(seconds=duration_seconds, minutes=LOOKAROUND_MINUTES)

    try:
        resp = requests.get(
            f"{GRAPH_BASE}/users/{upn}/calendarView",
            headers={"Authorization": f"Bearer {token}", "Prefer": 'outlook.timezone="UTC"'},
            params={
                "startDateTime": window_start.strftime("%Y-%m-%dT%H:%M:%S"),
                "endDateTime": window_end.strftime("%Y-%m-%dT%H:%M:%S"),
                "$select": "subject,attendees,start,end",
                "$top": "10",
            },
            timeout=10,
        )
        resp.raise_for_status()
        events = resp.json().get("value", [])
    except Exception:
        return []

    if not events:
        return []

    # Prvni vracena udalost - Graph uz razeni podle casu resi samo.
    best = events[0]
    return [
        a["emailAddress"]["name"]
        for a in best.get("attendees", [])
        if a.get("emailAddress", {}).get("name")
    ]
