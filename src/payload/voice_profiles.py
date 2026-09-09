#!/usr/bin/env python3
"""Automaticke rozpoznani mluvciho podle hlasu (hlasovy otisk) - misto
rucniho vyplnovani jmen v _speakers.json se kazdy diarizovany mluvci
porovna s dopredu zaznamenanymi hlasovymi profily kolegu. Pri dostatecne
podobnosti se jmeno prideli automaticky primo v transcribe_meeting.ps1;
neznamy hlas (host, nekdo nezaregistrovany) zustane jako SPEAKER_00/01/...
a jde doplnit puvodnim rucnim apply_speaker_names.py.

Pouziti (jednou na cloveka, kratka 10-30s cista nahravka jeho hlasu):
    python voice_profiles.py enroll "Jan Novak" cesta/k/nahravce.wav

Pouziva stejny embedding model, jaky uz diarizace mimochodem stahuje
(pyannote/wespeaker-voxceleb-resnet34-LM) - zadne dalsi stahovani.

POZNAMKA K NACITANI ZVUKU: pyannote.audio v tomhle prostredi vyzaduje
torchcodec pro primo nacteni souboru (chybi mu spravne DLL) a torchaudio
nema zadny funkcni backend take - proto se zvuk cte rucne pres stdlib
`wave` modul (funguje spolehlive na WAV, ktery uz diarizace/transcribe
stejne produkuji pres ffmpeg) a preda se primo jako waveform tensor.
"""
import json
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np
import torch

# NE Path(__file__).resolve().parent - transcribe_meeting.ps1 kopiruje tenhle
# soubor do docasne slozky pro kazdy beh (kvuli importu), takze __file__ by
# ukazovalo jinam pri kazdem spusteni. Kotva na stabilni %USERPROFILE%\whisper-setup,
# stejne jako zbytek kodu (WorkDir v transcribe_meeting.ps1/stages.ps1).
PROFILES_DIR = Path.home() / "whisper-setup" / "voice-profiles"
SIMILARITY_THRESHOLD = 0.75  # konzervativni - radsi neznamy mluvci nez spatne prirazene jmeno

_inference = None


def _get_inference():
    global _inference
    if _inference is None:
        from pyannote.audio import Inference, Model
        model = Model.from_pretrained("pyannote/wespeaker-voxceleb-resnet34-LM")
        _inference = Inference(model, window="whole")
    return _inference


def _load_waveform(path: str) -> dict:
    with wave.open(path, "rb") as wf:
        n_channels = wf.getnchannels()
        sample_rate = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if n_channels > 1:
        samples = samples.reshape(-1, n_channels).mean(axis=1)
    return {"waveform": torch.from_numpy(samples).unsqueeze(0), "sample_rate": sample_rate}


def _embed(audio_path: str) -> np.ndarray:
    # Vzdy prevest pres ffmpeg do ciste WAV nejdriv - vstup pro enroll() muze
    # byt cokoliv (m4a z Hlasoveho zaznamnika, mp4 z Meetily,...), ne jen WAV.
    with tempfile.TemporaryDirectory() as tmpdir:
        wav_path = str(Path(tmpdir) / "audio.wav")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", audio_path, wav_path],
            check=True,
        )
        return _get_inference()(_load_waveform(wav_path))


def enroll(name: str, audio_path: str) -> None:
    """Zaznamena hlasovy profil dane osoby. audio_path muze byt jakykoliv
    format, ktery umi precist ffmpeg (m4a, mp4, mp3, wav, ...)."""
    embedding = _embed(audio_path)
    PROFILES_DIR.mkdir(parents=True, exist_ok=True)
    path = PROFILES_DIR / f"{name}.json"
    path.write_text(json.dumps(embedding.tolist()), encoding="utf-8")
    print(f"Hlasovy profil pro '{name}' ulozen: {path}")


def _load_profiles() -> dict[str, np.ndarray]:
    profiles = {}
    if not PROFILES_DIR.is_dir():
        return profiles
    for path in PROFILES_DIR.glob("*.json"):
        try:
            profiles[path.stem] = np.array(json.loads(path.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError):
            continue
    return profiles


def identify(audio_path: str) -> str | None:
    """Vrati jmeno nejlepsi shody nad prahem podobnosti, jinak None
    (zadny zaznamenany profil, nebo zadny dost podobny)."""
    profiles = _load_profiles()
    if not profiles:
        return None
    try:
        embedding = _embed(audio_path)
    except Exception:  # noqa: BLE001 - rozpoznani hlasu je jen pomocne, nesmi shodit prepis
        return None
    best_name, best_score = None, -1.0
    for name, ref in profiles.items():
        score = float(np.dot(embedding, ref) / (np.linalg.norm(embedding) * np.linalg.norm(ref)))
        if score > best_score:
            best_name, best_score = name, score
    return best_name if best_score >= SIMILARITY_THRESHOLD else None


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "enroll":
        enroll(sys.argv[2], sys.argv[3])
    else:
        print(r'Pouziti: python voice_profiles.py enroll "Jmeno" cesta\k\nahravce.wav')
        raise SystemExit(1)
