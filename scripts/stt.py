#!/home/userzoltan/.whisper-venv/bin/python3
"""
stt.py -- Speech-to-text a Marveen rendszerhez
Használat: python3 stt.py <audio_fajl>
Kimenet: átírt szöveg stdout-ra
"""
import sys
import os

def main():
    if len(sys.argv) != 2:
        print("Használat: stt.py <audio_fajl>", file=sys.stderr)
        sys.exit(1)

    audio_path = sys.argv[1]
    if not os.path.exists(audio_path):
        print(f"Fájl nem létezik: {audio_path}", file=sys.stderr)
        sys.exit(1)

    try:
        from faster_whisper import WhisperModel
        model = WhisperModel("small", device="cpu", compute_type="int8")
        segments, info = model.transcribe(audio_path, language="hu", beam_size=5)
        text = " ".join(s.text.strip() for s in segments).strip()
        if text:
            print(text)
        else:
            print("[üres hangüzenet]")
    except Exception as e:
        print(f"STT hiba: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
