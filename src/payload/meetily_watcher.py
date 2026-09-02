#!/usr/bin/env python3
"""Reprocesses one Meetily recording with faster-whisper + WhisperX and writes
speaker-labeled segments back into Meetily's own SQLite database.

Použití: python meetily_watcher.py <meeting_id>
Vyžaduje spuštěný transcribe_meeting.ps1 vedle sebe (ve stejné složce).
"""
import json
import os
import subprocess
import sqlite3
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

from export_transcript import export_transcript

# Windows (Tauri konvence): %APPDATA%\<bundle-id>\... - ZATIM NEOVERENO na
# reálné instalaci, jen odhad podle Tauri defaultů. Až appka poběží na
# testovacím Windows stroji, zkontroluj skutečnou cestu a uprav.
DB_PATH = Path(os.environ["APPDATA"]) / "com.meetily.ai" / "meeting_minutes.sqlite"
SCRIPT_DIR = Path(__file__).resolve().parent
TRANSCRIBE_SCRIPT = SCRIPT_DIR / "transcribe_meeting.ps1"
# Mimo Meetily nahrávací složku - psaní souborů přímo do folder_path spustí
# Meetily vlastní sledování složky a appka nahrávku znovu naimportuje jako
# duplicitní meeting (ověřeno v praxi na Macu, na Windows nutno ověřit znovu).
STATE_DIR = SCRIPT_DIR / "watcher-state"


def get_meeting(conn, meeting_id):
    row = conn.execute(
        "SELECT id, title, folder_path FROM meetings WHERE id = ?", (meeting_id,)
    ).fetchone()
    if row is None:
        raise SystemExit(f"Meeting {meeting_id} nenalezen v databázi.")
    return row


def resolve_audio_path(folder_path: str) -> Path:
    """Meetily nahrávky nejsou vždy .wav - starší/kratší nahrávky mají .mp4.
    Skutečný název je v metadata.json (klíč "audio_file"), audio.wav je jen
    nejčastější případ, ne pravidlo."""
    folder = Path(folder_path)
    metadata_path = folder / "metadata.json"
    if metadata_path.exists():
        try:
            audio_file = json.loads(metadata_path.read_text()).get("audio_file")
            if audio_file and (folder / audio_file).exists():
                return folder / audio_file
        except (json.JSONDecodeError, OSError):
            pass
    return folder / "audio.wav"


def diarized_output_path(meeting_id: str) -> Path:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    return STATE_DIR / f"{meeting_id}_diarized.json"


def backup_existing_transcript(conn, meeting_id, folder_path):
    rows = conn.execute(
        "SELECT * FROM transcripts WHERE meeting_id = ? ORDER BY audio_start_time",
        (meeting_id,),
    ).fetchall()
    cols = [d[0] for d in conn.execute("SELECT * FROM transcripts LIMIT 1").description]
    backup = [dict(zip(cols, r)) for r in rows]
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    backup_path = STATE_DIR / f"{meeting_id}_original_backup.json"
    backup_path.write_text(json.dumps(backup, ensure_ascii=False, indent=2))
    print(f"-> Puvodni transkript zazalohovan do: {backup_path}")
    return len(backup)


def run_pipeline(audio_path, out_json):
    subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         str(TRANSCRIBE_SCRIPT), str(audio_path), str(out_json)],
        check=True,
    )
    return json.loads(out_json.read_text())


def replace_transcript(conn, meeting_id, segments):
    conn.execute("DELETE FROM transcripts WHERE meeting_id = ?", (meeting_id,))
    now = datetime.now(timezone.utc).isoformat()
    for seg in segments:
        conn.execute(
            """INSERT INTO transcripts
               (id, meeting_id, transcript, timestamp, audio_start_time, audio_end_time, duration, speaker)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                f"transcript-{uuid.uuid4()}",
                meeting_id,
                seg["text"],
                now,
                seg["start"],
                seg["end"],
                seg["end"] - seg["start"],
                seg["speaker"],
            ),
        )
    conn.commit()


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Pouziti: python meetily_watcher.py <meeting_id>")
    meeting_id = sys.argv[1]

    conn = sqlite3.connect(DB_PATH)
    meeting_id, title, folder_path = get_meeting(conn, meeting_id)
    audio_path = resolve_audio_path(folder_path)
    if not audio_path.exists():
        raise SystemExit(f"Zvukovy soubor nenalezen v {folder_path}")

    print(f"-> Zpracovavam meeting: {title} ({meeting_id})")
    n_backed_up = backup_existing_transcript(conn, meeting_id, folder_path)
    print(f"-> Zazalohovano {n_backed_up} puvodnich radku transkriptu.")

    out_json = diarized_output_path(meeting_id)
    segments = run_pipeline(audio_path, out_json)
    print(f"-> Novy transkript: {len(segments)} segmentu se jmeny mluvcich.")

    replace_transcript(conn, meeting_id, segments)
    print("-> Zapsano zpet do Meetily databaze. Hotovo.")
    export_transcript(meeting_id, title, segments)
    conn.close()


if __name__ == "__main__":
    main()
