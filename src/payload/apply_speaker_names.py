#!/usr/bin/env python3
"""Aplikuje ručně vyplněné jméno mluvčích (speaker_map JSON) do Meetily DB
a znovu vyexportuje přepis do sdílené složky se jmény místo Speaker_00/01.

Použití: python apply_speaker_names.py <meeting_id>
Vyžaduje, aby už existoval <meeting_id>_speakers.json ve watcher-state
(vzniká automaticky při zpracování schůzky) a byl ručně vyplněný.
"""
import json
import sqlite3
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from export_transcript import export_transcript, load_speaker_map, speaker_map_path  # noqa: E402
from meetily_watcher import DB_PATH, diarized_output_path, get_meeting  # noqa: E402


def rename_in_db(conn: sqlite3.Connection, meeting_id: str, speaker_map: dict[str, str]) -> int:
    updated = 0
    for label, name in speaker_map.items():
        if not name:
            continue
        cur = conn.execute(
            "UPDATE transcripts SET speaker = ? WHERE meeting_id = ? AND speaker = ?",
            (name, meeting_id, label),
        )
        updated += cur.rowcount
    conn.commit()
    return updated


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Pouziti: python apply_speaker_names.py <meeting_id>")
    meeting_id = sys.argv[1]

    speaker_map = load_speaker_map(meeting_id)
    if not speaker_map or not any(speaker_map.values()):
        raise SystemExit(
            f"Vyplň nejdřív jména v {speaker_map_path(meeting_id)}, pak spusť znovu."
        )

    out_json = diarized_output_path(meeting_id)
    if not out_json.exists():
        raise SystemExit(f"Diarizovaný přepis nenalezen: {out_json}")
    segments = json.loads(out_json.read_text())

    conn = sqlite3.connect(DB_PATH)
    _, title, _ = get_meeting(conn, meeting_id)
    n_updated = rename_in_db(conn, meeting_id, speaker_map)
    conn.close()
    print(f"-> Prepsano {n_updated} radku v Meetily DB na realna jmena.")

    export_transcript(meeting_id, title, segments)


if __name__ == "__main__":
    main()
