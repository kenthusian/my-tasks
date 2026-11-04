"""Run once after `flutter create`: lets the app talk to the sync server.

Adds the INTERNET / ACCESS_NETWORK_STATE permissions and allows plain-HTTP
traffic (the demo server is http://, not https://).
"""
import pathlib
import sys

manifest = pathlib.Path(__file__).resolve().parent.parent / "android/app/src/main/AndroidManifest.xml"
if not manifest.exists():
    sys.exit("Run `flutter create --platforms=android .` first (manifest not found).")

text = manifest.read_text(encoding="utf-8")
perms = ""
for p in ("INTERNET", "ACCESS_NETWORK_STATE"):
    line = f'android.permission.{p}'
    if line not in text:
        perms += f'    <uses-permission android:name="{line}"/>\n'
if perms:
    text = text.replace("<application", perms + "    <application", 1)
if "usesCleartextTraffic" not in text:
    text = text.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
manifest.write_text(text, encoding="utf-8")
print("AndroidManifest.xml patched.")
