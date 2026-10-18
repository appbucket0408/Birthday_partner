#!/usr/bin/env python3
"""Adds strangers, posts and reports to the LOCAL stack for trying report
and block by hand. Run supabase/seed_dummy_users.py first: this builds on
its accounts (b_02 has a birthday today, and YOU celebrate b_02).

    supabase start
    python3 supabase/seed_dummy_users.py
    python3 supabase/seed_moderation_demo.py

New accounts (sign in with code 123456 -- local_dev_otp.sql accepts it for
any number):

    Priya Sharma  9000000201   friendly; a photo wish on b_02's wall
    Spam Sam      9000000202   spam on b_02's wall and on b_03's
    Troll Tom     9000000203   rude wish on b_02's wall AND on yours

None of them is someone you celebrate, so as YOU (default 9876543210):

  * Feed: all their posts about b_02 show up (a member's wall is public).
    Tap "..." on one to report it, or block its author.
  * b_02's page: the same posts are on the wall. Open one, "..." -> report.
  * Your Profile: Troll Tom's wish is on your wall. Open it and block him.
  * Settings -> Blocked people: unblock him again.

Reports already waiting in the ops console (so the queue is not empty):

  * Spam Sam's post on b_02's wall, reported by b_03 AND b_04 (shows
    "2 open reports").
  * Troll Tom's post on b_02's wall, reported by b_07.
  * Troll Tom himself, reported by b_06 (a person report: Dismiss only).

Ops console staff account (local only):

    email     ops@candlewish.test
    password  candlewish-ops-local
    run       fvm flutter run -t lib/main_ops.dart \\
                --dart-define=SUPABASE_ANON_KEY=<anon key>

Like seed_dummy_users.py, every step goes through the public endpoints the
app uses, except ONE: making the ops account staff. profiles.is_staff is
not client-writable (that is the point of it), so that single UPDATE runs
in the local database container.

Safe to re-run: a repeated wish or report is skipped.

Local only: refuses any URL that is not 127.0.0.1/localhost.
"""

import datetime as dt
import json
import os
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zlib

URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321")
ME = os.environ.get("SEED_ME", "+919876543210")
OTP = "123456"
DB_CONTAINER = os.environ.get("SEED_DB_CONTAINER", "supabase_db_birthday_app")

STAFF_EMAIL = "ops@candlewish.test"
STAFF_PASSWORD = "candlewish-ops-local"

STRANGERS = {
    "priya": {"phone": "+919000000201", "name": "Priya Sharma"},
    "sam": {"phone": "+919000000202", "name": "Spam Sam"},
    "tom": {"phone": "+919000000203", "name": "Troll Tom"},
}


def fail(msg):
    print(f"FAILED: {msg}")
    sys.exit(1)


if not URL.startswith(("http://127.0.0.1:", "http://localhost:")):
    fail(f"refusing to run against {URL} -- local stack only.")

try:
    ANON = json.loads(
        subprocess.run(
            ["supabase", "status", "-o", "json"],
            capture_output=True, text=True, check=True,
        ).stdout
    )["ANON_KEY"]
except Exception as e:  # noqa: BLE001 -- any failure means "stack not up"
    fail(f"could not read the anon key ({e}). Is `supabase start` running?")


class RateLimited(Exception):
    pass


def call(method, path, token=None, body=None, ok_codes=(), raw=None,
         content_type="application/json", retry_429=False):
    headers = {"apikey": ANON, "content-type": content_type}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if method in ("POST", "PATCH", "DELETE") and path.startswith("/rest/"):
        headers["Prefer"] = "return=representation"
    data = raw if raw is not None else (
        json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(URL + path, data=data, method=method,
                                 headers=headers)
    try:
        with urllib.request.urlopen(req) as res:
            text = res.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        if e.code in ok_codes:
            return None
        if retry_429 and e.code == 429:
            raise RateLimited() from e
        fail(f"{method} {path} -> {e.code}: {text}")


def sign_in(phone):
    # GoTrue allows one code per number every few seconds (max_frequency),
    # and seed_dummy_users.py may have just asked for the same numbers.
    for attempt in range(4):
        try:
            call("POST", "/auth/v1/otp", body={"phone": phone}, retry_429=True)
            break
        except RateLimited:
            time.sleep(6)
    else:
        fail(f"OTP for {phone} stayed rate-limited")
    s = call("POST", "/auth/v1/verify",
             body={"phone": phone, "token": OTP, "type": "sms"})
    token = s["access_token"]
    person_id = call("POST", "/functions/v1/claim_profile", token)["person_id"]
    return {"token": token, "uid": s["user"]["id"], "person_id": person_id}


def profile(user):
    return call("GET", f"/rest/v1/profiles?id=eq.{user['uid']}"
                "&select=handle,display_name,birth_month,birth_day",
                user["token"])[0]


def occasion_year(user, today):
    """Birthday.occasionYear (lib/models/birthday.dart): the occurrence
    nearest to today, ties going to the past."""
    p = profile(user)
    if not p["birth_month"]:
        return today.year
    m, d = p["birth_month"], p["birth_day"]
    this_year = dt.date(today.year, m, d)
    nxt = this_year if this_year >= today else dt.date(today.year + 1, m, d)
    prev = this_year if this_year <= today else dt.date(today.year - 1, m, d)
    return prev.year if (today - prev) <= (nxt - today) else nxt.year


def png(width, height, rgb):
    """A plain one-colour PNG, built by hand so the script needs nothing
    beyond the standard library."""
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))
    row = b"\x00" + bytes(rgb) * width
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * height, 9))
            + chunk(b"IEND", b""))


def existing_wish(author, subject):
    rows = call("GET",
                f"/rest/v1/wishes?author_profile_id=eq.{author['uid']}"
                f"&subject_person_id=eq.{subject['person_id']}"
                "&kind=eq.message&select=id&order=id.desc&limit=1",
                author["token"])
    return rows[0]["id"] if rows else None


def wish(author, subject, body, today, photo_rgb=None):
    """Posts one wish (the app allows one per person per birthday) and
    returns its id, or the id of the one posted on a previous run."""
    found = existing_wish(author, subject)
    if found:
        return found, False
    photo_path = None
    if photo_rgb:
        photo_path = f"{author['uid']}/{int(time.time() * 1000)}.png"
        call("POST", f"/storage/v1/object/wish_photos/{photo_path}",
             author["token"], raw=png(720, 540, photo_rgb),
             content_type="image/png")
    row = call("POST", "/rest/v1/wishes", author["token"], {
        "author_profile_id": author["uid"],
        "subject_person_id": subject["person_id"],
        "body": body,
        "occasion_year": occasion_year(subject, today),
        **({"photo_path": photo_path} if photo_path else {}),
    })[0]
    return row["id"], True


def celebrate(user, phone, name):
    res = call("POST", "/functions/v1/add_celebrations", user["token"],
               {"contacts": [{"phone": phone, "name": name}]})
    return res["results"][0]["status"]


today = dt.date.today()

print("Signing in the accounts from seed_dummy_users.py")
dummies = {d: sign_in("+91" + str(d) * 10) for d in (2, 3, 4, 6, 7)}
if not profile(dummies[2])["birth_month"]:
    fail("b_02 has no birthday -- run supabase/seed_dummy_users.py first.")
me = sign_in(ME) if ME != "none" else None
if me and not profile(me)["birth_month"]:
    # Only when it has none: Troll Tom's wish on your wall needs a birthday
    # to attach to. Finishing onboarding in the app sets your real one.
    call("PATCH", f"/rest/v1/profiles?id=eq.{me['uid']}", me["token"],
         {"birth_month": 3, "birth_day": 12, "birth_year": 1995})
    print(f"  you ({ME[3:]}) had no birthday: set to 12 March 1995")

print("\nCreating strangers")
people = {}
for key, s in STRANGERS.items():
    u = sign_in(s["phone"])
    call("PATCH", f"/rest/v1/profiles?id=eq.{u['uid']}", u["token"], {
        "handle": s["name"].lower().replace(" ", "_"),
        "display_name": s["name"],
        "city": "Jaipur",
    })
    people[key] = u
    print(f"  {s['name']:<13} {s['phone'][3:]}")

# A wish needs a celebration edge to its subject (wishes_insert_own).
print("\nConnecting them to the people they post about")
targets = [("priya", "+912222222222", "b_02"),
           ("sam", "+912222222222", "b_02"),
           ("sam", "+913333333333", "b_03"),
           ("tom", "+912222222222", "b_02")]
if me:
    targets.append(("tom", ME, "you"))
for key, phone, label in targets:
    status = celebrate(people[key], phone, label)
    print(f"  {STRANGERS[key]['name']} -> {label}: {status}")

print("\nPosting")
posts = {}
posts["priya_b02"], new = wish(
    people["priya"], dummies[2],
    "Happy birthday! Baked this just for you 🎂", today,
    photo_rgb=(244, 143, 177))
print(f"  Priya -> b_02 (photo)  {'new' if new else 'already there'}")
posts["sam_b02"], new = wish(
    people["sam"], dummies[2],
    "🔥 Earn ₹50,000 a day from home!! DM me now 💸💸 limited spots", today)
print(f"  Sam   -> b_02 (spam)   {'new' if new else 'already there'}")
posts["sam_b03"], new = wish(
    people["sam"], dummies[3],
    "Crypto giveaway 🚀 send 1 BTC get 2 back, link in my bio", today)
print(f"  Sam   -> b_03 (spam)   {'new' if new else 'already there'}")
posts["tom_b02"], new = wish(
    people["tom"], dummies[2],
    "lol who even celebrates you 🙄", today)
print(f"  Tom   -> b_02 (rude)   {'new' if new else 'already there'}")
if me:
    if profile(me)["birth_month"]:
        posts["tom_me"], new = wish(
            people["tom"], me, "Another year older and still boring 😴", today)
        print(f"  Tom   -> you  (rude)   {'new' if new else 'already there'}")
    else:
        print("  Tom   -> you  skipped -- finish your profile (birthday) first")

print("\nFiling reports for the ops queue")


def report_wish(reporter, wish_id, reason, label):
    call("POST", "/rest/v1/rpc/rpc_report_wish", reporter["token"],
         {"p_wish_id": wish_id, "p_reason": reason})
    print(f"  {label}")


report_wish(dummies[3], posts["sam_b02"], "spam", "b_03 reported Spam Sam's post")
report_wish(dummies[4], posts["sam_b02"], "spam", "b_04 reported Spam Sam's post")
report_wish(dummies[7], posts["tom_b02"], "harassment",
            "b_07 reported Troll Tom's post")
call("POST", "/rest/v1/rpc/rpc_report_user", dummies[6]["token"],
     {"p_profile_id": people["tom"]["uid"], "p_reason": "harassment",
      "p_note": "Keeps posting mean things on my friends' walls"})
print("  b_06 reported Troll Tom")

print("\nOps console staff account")
signup = call("POST", "/auth/v1/signup",
              body={"email": STAFF_EMAIL, "password": STAFF_PASSWORD},
              ok_codes=(400, 422))
print(f"  {STAFF_EMAIL}: {'created' if signup else 'already exists'}")
# The one direct write: is_staff is deliberately not client-writable.
try:
    subprocess.run(
        ["docker", "exec", DB_CONTAINER, "psql", "-U", "postgres", "-Atc",
         "update public.profiles set is_staff = true, display_name = 'Ops' "
         "where id = (select id from auth.users "
         f"where email = '{STAFF_EMAIL}')"],
        capture_output=True, text=True, check=True)
    print("  marked as staff")
except Exception as e:  # noqa: BLE001
    print(f"  could not mark as staff ({e}). Run this in the local SQL editor:")
    print("    update public.profiles set is_staff = true where id = "
          f"(select id from auth.users where email = '{STAFF_EMAIL}');")

print(f"\nDone. Sign in as you ({ME[3:]}) with code {OTP} and open the Feed.")
print(f"Ops console: {STAFF_EMAIL} / {STAFF_PASSWORD}")
