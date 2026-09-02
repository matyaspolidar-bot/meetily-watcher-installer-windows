# Přepis + rozpoznání mluvčích na jednom audio souboru - analogie transcribe_meeting.sh.
# Pouziti: transcribe_meeting.ps1 cesta\k\audio.wav [vystup.json]
#
# Poradi je zamerne diarizace -> prepis (ne naopak): Whisper pozna jazyk jen
# jednou za cely vstup, takze pri smichane cestine/anglictine v jednom souboru
# by mensinovy jazyk vubec neprepsal. Kdyz se ale vstup nejdriv rozdeli podle
# mluvcich a Whisper se pusti zvlast na kazdy usek, pozna jazyk spravne pro
# kazdy usek zvlast.
#
# Na rozdil od Mac verze (mlx-whisper v samostatnem venv) pouziva Windows
# JEDEN venv (whisperx-env) pro diarizaci i prepis - faster-whisper, na kterem
# whisperx uz interne stavi.
param(
    [Parameter(Mandatory)][string]$Audio,
    [string]$Out = (Join-Path $env:TEMP "transcribe_meeting_output.json")
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $Audio)) {
    Write-Host "Soubor nenalezen: $Audio"
    exit 1
}

$WorkDir = Join-Path $env:USERPROFILE "whisper-setup"
$Py = Join-Path $WorkDir "whisperx-env\Scripts\python.exe"
$Tmp = Join-Path $env:TEMP ([guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

try {
    $diarizationJson = Join-Path $Tmp "diarization.json"
    $diarizeScript = Join-Path $Tmp "diarize.py"

    Write-Host "-> Rozpoznavam mluvci (WhisperX/pyannote)..."
    @'
import sys, json
from whisperx.diarize import DiarizationPipeline

audio, out = sys.argv[1], sys.argv[2]
# Vynuceno explicitne: vychozi model WhisperX (speaker-diarization-community-1)
# se v Mac testech presegmentovaval vyrazneji nez tento.
dp = DiarizationPipeline(model_name='pyannote/speaker-diarization-3.1', device='cpu')
df = dp(audio)
records = df[['start', 'end', 'speaker']].to_dict('records')

merged = []
GAP_SECONDS = 1.0
for r in records:
    if merged and merged[-1]['speaker'] == r['speaker'] and r['start'] - merged[-1]['end'] < GAP_SECONDS:
        merged[-1]['end'] = r['end']
    else:
        merged.append(dict(r))

json.dump(merged, open(out, 'w'), ensure_ascii=False)
'@ | Set-Content -Path $diarizeScript -Encoding UTF8

    & $Py $diarizeScript $Audio $diarizationJson
    if ($LASTEXITCODE -ne 0) { throw "Diarizace selhala (kod $LASTEXITCODE)." }

    Write-Host "-> Prepisuji po usecich mluvcich (faster-whisper, jazyk se pozna zvlast pro kazdy usek)..."
    $transcribeScript = Join-Path $Tmp "transcribe.py"
    @'
import json
import os
import subprocess
import sys
import tempfile

from faster_whisper import WhisperModel

END_PADDING_SECONDS = 0.3  # diarizacni hranice nekdy urizne posledni slovo vety

audio_path, diar_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
segments_in = json.load(open(diar_path))

model = WhisperModel("large-v3", device="cpu", compute_type="int8")

merged_out = []
with tempfile.TemporaryDirectory() as tmpdir:
    for i, seg in enumerate(segments_in):
        start, end, speaker = seg['start'], seg['end'], seg['speaker']
        padded_end = end + END_PADDING_SECONDS
        slice_path = os.path.join(tmpdir, f"slice_{i}.wav")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", audio_path,
             "-ss", str(start), "-to", str(padded_end), slice_path],
            check=True,
        )
        result_segments, info = model.transcribe(slice_path)
        text = " ".join(s.text.strip() for s in result_segments).strip()
        if text:
            merged_out.append({
                'start': start,
                'end': end,
                'text': text,
                'speaker': speaker,
                'language': info.language,
            })

json.dump(merged_out, open(out_path, 'w'), ensure_ascii=False, indent=2)

lines = []
last_speaker = None
for seg in merged_out:
    ts = f"[{int(seg['start']//60):02d}:{int(seg['start']%60):02d}]"
    if seg['speaker'] != last_speaker:
        lines.append(f"\n{ts} {seg['speaker']}:")
        last_speaker = seg['speaker']
    lines.append(seg['text'])

print(' '.join(lines).strip())
'@ | Set-Content -Path $transcribeScript -Encoding UTF8

    & $Py $transcribeScript $Audio $diarizationJson $Out
    if ($LASTEXITCODE -ne 0) { throw "Prepis selhal (kod $LASTEXITCODE)." }
}
finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Hotovo. Strukturovany vystup (JSON) ulozen do: $Out"
