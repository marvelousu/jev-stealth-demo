"""Stage a Windows demo with its public service URL and a bundled Godot runtime.

No credential input: the operator configures Jev on a separate hosted service.
This development bundle uses the existing Godot binary; it is not a signed,
optimized release export. Python and Godot installation are not needed to play.
"""
from __future__ import annotations

import argparse
import ipaddress
import json
import re
from pathlib import Path
import shutil
import subprocess
import zipfile
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
CLIENT_FILES = ("project.godot", "main.tscn", "main.gd", "level.gd", "tactics.gd", "replay.gd", "mission.gd", "briefing.gd", "decision_history.gd", "decision_gate.gd", "mission_feedback.gd", "explanation.gd", "tactical_view.gd", "courtyard.gd", "courtyard.tscn", "courtyard_replay.gd")


def public_url(value: str) -> str:
    if any(ord(c) < 33 for c in value) or any(c in value for c in '\\"'):
        raise ValueError("Use a public HTTPS URL without whitespace or escapes")
    url = urlsplit(value)
    if (url.scheme != "https" or not url.hostname or url.username is not None
            or url.password is not None or url.query or url.fragment):
        raise ValueError("Use HTTPS without credentials, query parameters or fragments")
    host = url.hostname.lower()
    if host == "localhost" or host.endswith((".localhost", ".local", ".invalid", ".test", ".example")):
        raise ValueError("Distribution requires a public service hostname")
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        address = None
    if address is not None and not address.is_global:
        raise ValueError("Distribution requires a public service address")
    if url.port is not None and url.port != 443:
        raise ValueError("Distribution uses standard HTTPS port 443")
    return value.rstrip("/")


def stage_client(destination: Path, service_url: str) -> None:
    endpoint = public_url(service_url)
    # Never copy the whole working tree: server, key-entry tools and QA stay here.
    destination.mkdir(parents=True, exist_ok=False)
    for name in CLIENT_FILES:
        shutil.copyfile(ROOT / name, destination / name)
    audio = destination / "audio"
    audio.mkdir()
    for name in ("alert", "noise", "pickup", "shot", "smoke"):
        shutil.copyfile(ROOT / "audio" / f"{name}.wav", audio / f"{name}.wav")
    shutil.copyfile(ROOT / "audio" / "bgm.ogg", audio / "bgm.ogg")
    settings = destination / "project.godot"
    content = settings.read_text(encoding="utf-8")
    content = re.sub(r'(?ms)^\[jev\]\s*\n.*?(?=^\[|\Z)', '', content)
    settings.write_text(content.rstrip() + '\n\n[jev]\nservice_url=' + json.dumps(endpoint) + '\n', encoding="utf-8")


def archive_client(destination: Path) -> Path:
    archive = destination.with_name(destination.name + ".zip")
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED) as bundle:
        for path in destination.rglob("*"):
            relative = path.relative_to(destination).as_posix()
            if path.is_file() and not relative.startswith((".godot/editor/", ".godot/shader_cache/")):
                bundle.write(path, destination.name + "/" + relative)
    return archive


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--service-url", required=True, type=public_url)
    parser.add_argument("--godot", required=True, type=Path, help="Existing Windows Godot 4.6.3 GUI executable")
    parser.add_argument("--output", required=True, type=Path, help="New directory; existing data is never overwritten")
    parser.add_argument("--zip", action="store_true", help="Also create a sibling ZIP for recipients")
    args = parser.parse_args()
    licenses = [ROOT / name for name in ("LICENSE", "GODOT-LICENSE.txt", "GODOT-COPYRIGHT.txt")]
    for license_path in licenses:
        if not license_path.exists():
            raise FileNotFoundError(f"{license_path.name} is required for distribution")
    runtime = args.godot.resolve(strict=True)
    version = subprocess.run([str(runtime), "--version"], capture_output=True, text=True, check=True, timeout=20)
    if not version.stdout.strip().startswith("4.6.3.stable"):
        parser.error("Use Godot 4.6.3 stable, matching this demo")
    destination = args.output.resolve()
    stage_client(destination, args.service_url)
    shutil.copyfile(runtime, destination / "RELAY.exe")
    subprocess.run([str(runtime), "--headless", "--editor", "--import", "--quit", "--path", str(destination)], check=True, timeout=120)
    (destination / "Play.cmd").write_text('@echo off\nstart "" "%~dp0RELAY.exe" --path "%~dp0." res://courtyard.tscn -- --play\n', encoding="ascii")
    (destination / "Courtyard.cmd").write_text('@echo off\nstart "" "%~dp0RELAY.exe" --path "%~dp0." res://courtyard.tscn\n', encoding="ascii")
    (destination / "Legacy.cmd").write_text('@echo off\nstart "" "%~dp0RELAY.exe" --path "%~dp0." res://main.tscn\n', encoding="ascii")
    for license_path in licenses:
        shutil.copyfile(license_path, destination / license_path.name)
    (destination / "README.txt").write_text(
        "RELAY development demo\nRun Play.cmd. No key or software installation needed.\n"
        "Internet is required for Jev. If unavailable, enemy AI falls back to local rules.\n"
        "Quiet background music loops in-game. B or the BGM button toggles music only; this preference is saved.\n"
        "WASD move, Shift crouch, mouse aim, click fire, Q single noise, F repeating noise, G smoke, E interact.\n"
        "Press E near the northwest radio relay to toggle power. OFF stops distant enemy information sharing; nearby communication and individual senses remain.\n"
        "Hold E 1.2 seconds to take the case; hold E 2.5 seconds at an exit. Taking damage interrupts.\n"
        "Six bullets; three enemy hits are lethal. Carrying the case slows movement. M switches AI; R restarts.\n"
        "Courtyard: ordinary health; detection, radio coordination, pursuit and gunfire; Jev refines the same immediate local response; R to play, F8 compare.\n"
        "F8 compares the same sequence in rules then Jev mode. F6 records; F7 replays with the selected mode.\n"
        "Courtyard responds immediately with local AI; valid Jev replies can revise its plan asynchronously.\n"
        "Enemies keep moving while Jev is pending or unavailable.\n"
        "The F noisemaker repeats after 8 and 16 seconds. All enemy markers use the same color.\n"
        "In Courtyard, F9 selects a route: loop, rush, crouch, diversion, break_contact or double_back.\n"
        "Legacy.cmd starts the original main map; its F8/F10 comparison is invulnerable and tactical-only.\n"
        "Jev is not always better: inspect actual decisions with H, and check adopted/fallback counts.\n"
        "Free play has lethal damage; cover, distraction, radio power and smoke matter.\n"
        "H pauses play and opens the decision history: observed events, actual choices and same-state rule choices.\n"
        "Normal missions briefly announce actual enemy order changes, and end with an event timeline and retry hint.\n"
        "F1 explains who does what: game observation/memory -> tactic selection -> code assigns guards -> ordinary movement/shooting.\n"
        "F10 starts a guided comparison and pauses to explain a recorded decision in each mode. Close with F1 or Esc to watch the outcome.\n"
        "This bundle includes the Godot editor runtime and game source for prototype testing.\n"
        "The demo code and original audio are MIT licensed; see LICENSE. Godot and third-party components retain their own licenses.\n",
        encoding="utf-8")
    print(f"Client prepared: {destination}")
    if args.zip:
        archive = archive_client(destination)
        print(f"Client ZIP: {archive}")
    print("Hosting and a real Jev decision must be verified separately before sharing.")


if __name__ == "__main__":
    main()
