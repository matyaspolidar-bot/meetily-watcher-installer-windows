#!/usr/bin/env python3
"""Periodically checks Meetily's database for newly completed recordings
that haven't been reprocessed yet, and runs meetily_watcher's pipeline on
each of them. Meant to be triggered by Task Scheduler (repeating trigger,
viz register_scheduled_tasks.ps1), not run continuously itself - each
invocation checks once and exits.
"""
import json
import msvcrt
import sqlite3
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from export_transcript import export_transcript  # noqa: E402
from meetily_watcher import (  # noqa: E402
    DB_PATH,
    backup_existing_transcript,
    diarized_output_path,
    replace_transcript,
    resolve_audio_path,
    run_pipeline,
)

LOCK_PATH = SCRIPT_DIR / ".autowatch.lock"


def is_completed(folder_path: str) -> bool:
    meta = Path(folder_path) / "metadata.json"
    if not meta.exists():
        return False
    try:
        return json.loads(meta.read_text()).get("status") == "completed"
    except (json.JSONDecodeError, OSError):
        return False


def already_processed(meeting_id: str) -> bool:
    return diarized_output_path(meeting_id).exists()


def process_meeting(conn: sqlite3.Connection, meeting_id: str, title: str, folder_path: str) -> None:
    audio_path = resolve_audio_path(folder_path)
    if not audio_path.exists():
        print(f"[{meeting_id}] preskoceno, zvukovy soubor nenalezen v {folder_path}")
        return

    print(f"[{meeting_id}] '{title}' - nova nahravka, zpracovavam...")
    backup_existing_transcript(conn, meeting_id, folder_path)
    out_json = diarized_output_path(meeting_id)
    segments = run_pipeline(audio_path, out_json)
    replace_transcript(conn, meeting_id, segments)
    export_transcript(meeting_id, title, segments)
    print(f"[{meeting_id}] hotovo, {len(segments)} segmentu se jmeny mluvcich.")


def main() -> None:
    # msvcrt.locking je Windows ekvivalent fcntl.flock z Mac verze - zamek
    # se automaticky uvolni, kdyz se handle zavre (i pri padu procesu).
    lock_file = open(LOCK_PATH, "a+b")
    try:
        msvcrt.locking(lock_file.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        print("Uz bezi jiny beh autowatch, koncim.")
        lock_file.close()
        return

    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        "SELECT id, title, folder_path FROM meetings WHERE folder_path IS NOT NULL"
    ).fetchall()

    found_new = False
    for meeting_id, title, folder_path in rows:
        if already_processed(meeting_id) or not is_completed(folder_path):
            continue
        found_new = True
        try:
            process_meeting(conn, meeting_id, title, folder_path)
        except Exception as exc:  # noqa: BLE001 - log and keep checking other meetings
            print(f"[{meeting_id}] CHYBA: {exc}")

    if not found_new:
        print("Zadne nove nahravky.")

    conn.close()
    msvcrt.locking(lock_file.fileno(), msvcrt.LK_UNLCK, 1)
    lock_file.close()


if __name__ == "__main__":
    main()
