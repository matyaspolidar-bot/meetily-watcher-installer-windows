#!/usr/bin/env python3
"""Exportuje přepis schůzky do sdílené složky (mimo lokální Meetily DB) a
spravuje ruční mapování Speaker_00/01... na reálná jména.

Dokud není na tomhle Windows PC nastavené OneDrive (Addvery M365), SHARED_DIR
míří do lokální složky. Jakmile bude OneDrive nainstalované a přihlášené,
stačí přepsat SHARED_DIR na jeho cestu, např.:
    Path.home() / "OneDrive - Addvery" / "Prepisy-schuzek"
"""
import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
STATE_DIR = SCRIPT_DIR / "watcher-state"
SHARED_DIR = Path.home() / "Addvery-Prepisy-Sdilene"


def speaker_map_path(meeting_id: str) -> Path:
    return STATE_DIR / f"{meeting_id}_speakers.json"


def load_speaker_map(meeting_id: str) -> dict[str, str]:
    path = speaker_map_path(meeting_id)
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def ensure_speaker_map_template(meeting_id: str, segments: list[dict]) -> None:
    """Pokud mapování jmen ještě neexistuje, založí prázdnou šablonu se
    všemi labely mluvčích nalezenými v přepisu, ať ji jde rovnou vyplnit."""
    path = speaker_map_path(meeting_id)
    if path.exists():
        return
    labels = sorted({seg["speaker"] for seg in segments})
    template = {label: "" for label in labels}
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(template, ensure_ascii=False, indent=2))
    print(f"-> Sablona pro jmena mluvcich: {path}")
    print("   Vyplň jména a spusť: python apply_speaker_names.py " + meeting_id)


def render_transcript_md(title: str, meeting_id: str, segments: list[dict], speaker_map: dict[str, str]) -> str:
    lines = [f"# {title}", "", f"_meeting_id: {meeting_id}_", ""]
    for seg in segments:
        speaker = speaker_map.get(seg["speaker"]) or seg["speaker"]
        lines.append(f"**{speaker}** [{seg['start']:.1f}s]: {seg['text']}")
    return "\n\n".join(lines)


def export_transcript(meeting_id: str, title: str, segments: list[dict]) -> Path:
    ensure_speaker_map_template(meeting_id, segments)
    speaker_map = load_speaker_map(meeting_id)
    SHARED_DIR.mkdir(parents=True, exist_ok=True)
    out_path = SHARED_DIR / f"{title}_{meeting_id}.md"
    out_path.write_text(render_transcript_md(title, meeting_id, segments, speaker_map))
    print(f"-> Prepis ulozen do sdilene slozky: {out_path}")
    return out_path
