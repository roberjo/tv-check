"""Build and sign the "TV Pilot" Siri Shortcut: Dictate Text -> POST to the
concierge -> Speak the reply. Writes concierge/shortcut/TV Pilot.shortcut.

Usage: python3 concierge/make_shortcut.py [server_base_url]
"""
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
env = dict(l.split("=", 1) for l in (ROOT / ".env").read_text().split() if "=" in l)
host = subprocess.run(["scutil", "--get", "LocalHostName"], capture_output=True, text=True).stdout.strip()
base = sys.argv[1] if len(sys.argv) > 1 else f"http://{host}.local:{env.get('CONCIERGE_PORT', '8765')}"


def text(s):
    return {"Value": {"string": s, "attachmentsByRange": {}}, "WFSerializationType": "WFTextTokenString"}


def output_of(action_uuid, name):
    return {"Value": {"string": "￼", "attachmentsByRange": {"{0, 1}": {
        "OutputUUID": action_uuid, "Type": "ActionOutput", "OutputName": name}}},
        "WFSerializationType": "WFTextTokenString"}


def dictionary(pairs):
    return {"Value": {"WFDictionaryFieldValueItems": [
        {"WFItemType": 0, "WFKey": text(k), "WFValue": v} for k, v in pairs]},
        "WFSerializationType": "WFDictionaryFieldValue"}


dictate, fetch, speak = (str(uuid.uuid4()).upper() for _ in range(3))
workflow = {
    "WFWorkflowClientVersion": "2607.0.2",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowIcon": {"WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": 59511},
    "WFWorkflowImportQuestions": [],
    "WFWorkflowTypes": [],
    "WFWorkflowInputContentItemClasses": [],
    "WFWorkflowHasShortcutInputVariables": False,
    "WFWorkflowActions": [
        {"WFWorkflowActionIdentifier": "is.workflow.actions.dictatetext",
         "WFWorkflowActionParameters": {"UUID": dictate}},
        {"WFWorkflowActionIdentifier": "is.workflow.actions.downloadurl",
         "WFWorkflowActionParameters": {
             "UUID": fetch,
             "WFURL": f"{base}/command",
             "WFHTTPMethod": "POST",
             "WFHTTPBodyType": "JSON",
             "WFJSONValues": dictionary([("text", output_of(dictate, "Dictated Text"))]),
             "ShowHeaders": True,
             "WFHTTPHeaders": dictionary([("Authorization", text(f"Bearer {env['CONCIERGE_TOKEN']}"))]),
         }},
        {"WFWorkflowActionIdentifier": "is.workflow.actions.speaktext",
         "WFWorkflowActionParameters": {"UUID": speak, "WFText": output_of(fetch, "Contents of URL")}},
    ],
}

out_dir = ROOT / "concierge" / "shortcut"
out_dir.mkdir(exist_ok=True)
signed = out_dir / "TV Pilot.shortcut"
# `shortcuts sign` reports "file doesn't exist" for paths under ~/Documents, so sign in a temp dir.
with tempfile.TemporaryDirectory() as tmp:
    unsigned, tmp_signed = pathlib.Path(tmp, "unsigned.shortcut"), pathlib.Path(tmp, "signed.shortcut")
    unsigned.write_bytes(plistlib.dumps(workflow, fmt=plistlib.FMT_BINARY))
    r = subprocess.run(["shortcuts", "sign", "--mode", "anyone", "--input", str(unsigned), "--output", str(tmp_signed)],
                       capture_output=True, text=True)
    if tmp_signed.exists():
        shutil.copy(tmp_signed, signed)
print("server URL:", base)
print("sign:", r.returncode, (r.stdout + r.stderr).strip()[-400:])
print("wrote", signed if signed.exists() else "(not signed)")
