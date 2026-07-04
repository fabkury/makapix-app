#!/usr/bin/env python3
"""Google Play publisher for the Makapix Club app (androidpublisher v3).

Two subcommands, both driven by a service-account JSON key (see docs/play-release.md
for the one-time Play Console / GCP setup):

  next-code   Print the next free versionCode: 1 + max over every versionCode Play
              has ever seen for the package (all track releases + all uploaded
              bundles). Guards against "Version code N has already been used" —
              pubspec history can understate what Play has consumed.

  publish     Upload an .aab to a track and roll it out (status=completed), with
              optional release notes. Prints the resolved versionCode on success.

  promote     Copy the current release of one track onto another (no re-upload;
              the exact same versionCodes roll out on the destination track).
              e.g.  promote --from-track internal --to-track alpha

Normally invoked by release_android.ps1, not by hand.

Deps (not in the repo; install once):  pip install google-api-python-client google-auth
"""

import argparse
import sys
from pathlib import Path

PACKAGE = "club.makapix.app"
KEY_PATH = "app/android/play-service-account.json"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
NOTES_LIMIT = 500  # Play rejects release notes longer than 500 chars per language.


def die(msg: str, code: int = 2):
    print(f"play_publish: error: {msg}", file=sys.stderr)
    sys.exit(code)


def service(key_file: str):
    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build
    except ImportError:
        die("missing deps — run: pip install google-api-python-client google-auth")
    if not Path(key_file).is_file():
        die(f"service-account key not found: {key_file} (see docs/play-release.md)")
    creds = service_account.Credentials.from_service_account_file(key_file, scopes=[SCOPE])
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def used_version_codes(svc, package: str, edit_id: str) -> list[int]:
    codes: list[int] = []
    tracks = svc.edits().tracks().list(packageName=package, editId=edit_id).execute()
    for track in tracks.get("tracks", []):
        for release in track.get("releases", []):
            codes += [int(vc) for vc in release.get("versionCodes", []) or []]
    bundles = svc.edits().bundles().list(packageName=package, editId=edit_id).execute()
    codes += [int(b["versionCode"]) for b in bundles.get("bundles", []) or []]
    return codes


def cmd_next_code(args) -> None:
    svc = service(args.key)
    edit = svc.edits().insert(packageName=args.package, body={}).execute()
    codes = used_version_codes(svc, args.package, edit["id"])
    # Read-only edit; let it expire rather than deleting (delete needs no extra perms,
    # but failing to delete must not fail the query).
    try:
        svc.edits().delete(packageName=args.package, editId=edit["id"]).execute()
    except Exception:
        pass
    print(max(codes, default=0) + 1)


def read_notes(notes_file: str) -> str | None:
    if not notes_file:
        return None
    path = Path(notes_file)
    if not path.is_file():
        die(f"notes file not found: {notes_file}")
    text = path.read_text(encoding="utf-8").strip()
    if len(text) > NOTES_LIMIT:
        print(
            f"play_publish: warning: release notes are {len(text)} chars; truncating to {NOTES_LIMIT}",
            file=sys.stderr,
        )
        text = text[:NOTES_LIMIT]
    return text or None


def cmd_publish(args) -> None:
    from googleapiclient.http import MediaFileUpload

    aab = Path(args.aab)
    if not aab.is_file():
        die(f"AAB not found: {aab}")
    notes = read_notes(args.notes_file)

    svc = service(args.key)
    edit = svc.edits().insert(packageName=args.package, body={}).execute()
    edit_id = edit["id"]

    size_mb = aab.stat().st_size / (1024 * 1024)
    print(f"Uploading {aab} ({size_mb:.1f} MB) to '{args.track}'...")
    media = MediaFileUpload(str(aab), mimetype="application/octet-stream", resumable=True)
    uploaded = (
        svc.edits()
        .bundles()
        .upload(packageName=args.package, editId=edit_id, media_body=media)
        .execute(num_retries=3)
    )
    code = int(uploaded["versionCode"])
    print(f"Uploaded as versionCode {code}.")

    release = {"versionCodes": [str(code)], "status": "completed"}
    if args.release_name:
        release["name"] = args.release_name
    if notes:
        release["releaseNotes"] = [{"language": args.notes_language, "text": notes}]
    svc.edits().tracks().update(
        packageName=args.package,
        editId=edit_id,
        track=args.track,
        body={"track": args.track, "releases": [release]},
    ).execute()

    svc.edits().commit(packageName=args.package, editId=edit_id).execute()
    print(f"Rolled out versionCode {code} to '{args.track}'.")
    print(code)


def cmd_promote(args) -> None:
    svc = service(args.key)
    edit = svc.edits().insert(packageName=args.package, body={}).execute()
    edit_id = edit["id"]

    src = (
        svc.edits()
        .tracks()
        .get(packageName=args.package, editId=edit_id, track=args.from_track)
        .execute()
    )
    releases = [r for r in src.get("releases", []) if r.get("status") == "completed"]
    if not releases:
        die(f"no completed release found on track '{args.from_track}'")
    # Newest release = the one with the highest versionCode.
    source = max(releases, key=lambda r: max(int(vc) for vc in r.get("versionCodes", ["0"])))

    release = {
        "versionCodes": source["versionCodes"],
        # A "draft app" (no published release yet) only accepts draft releases; the
        # first rollout must then be started in the Play Console, which also sends
        # the app for its first review.
        "status": "draft" if args.draft else "completed",
    }
    if source.get("name"):
        release["name"] = source["name"]
    notes = read_notes(args.notes_file) if args.notes_file else None
    if notes:
        release["releaseNotes"] = [{"language": args.notes_language, "text": notes}]
    elif source.get("releaseNotes"):
        release["releaseNotes"] = source["releaseNotes"]

    svc.edits().tracks().update(
        packageName=args.package,
        editId=edit_id,
        track=args.to_track,
        body={"track": args.to_track, "releases": [release]},
    ).execute()
    svc.edits().commit(packageName=args.package, editId=edit_id).execute()
    codes = ", ".join(release["versionCodes"])
    how = "as a draft release" if args.draft else "and rolled out"
    print(f"Promoted versionCode(s) {codes} from '{args.from_track}' to '{args.to_track}' {how}.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", default=PACKAGE)
    parser.add_argument("--key", default=KEY_PATH, help="service-account JSON key path")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("next-code", help="print the next free versionCode")

    pub = sub.add_parser("publish", help="upload an .aab and roll it out to a track")
    pub.add_argument("--aab", required=True)
    pub.add_argument("--track", default="internal")
    pub.add_argument("--notes-file", default=None)
    pub.add_argument("--notes-language", default="en-US")
    pub.add_argument("--release-name", default=None, help="defaults to the versionName on Play")

    pro = sub.add_parser("promote", help="copy a track's current release onto another track")
    pro.add_argument("--from-track", required=True, dest="from_track")
    pro.add_argument("--to-track", required=True, dest="to_track")
    pro.add_argument("--notes-file", default=None, help="override notes; default: keep source notes")
    pro.add_argument("--notes-language", default="en-US")
    pro.add_argument("--draft", action="store_true", help="create as draft (required on a draft app)")

    args = parser.parse_args()
    if args.command == "next-code":
        cmd_next_code(args)
    elif args.command == "promote":
        cmd_promote(args)
    else:
        cmd_publish(args)


if __name__ == "__main__":
    main()
