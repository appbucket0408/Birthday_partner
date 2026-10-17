#!/usr/bin/env python3
"""Seeds the LOCAL stack with dummy accounts for trying the app by hand.

Sign in with any of these numbers and code 123456 (they are in
[auth.sms.test_otp]):

    b_02  2222222222   birthday TODAY            (Dashboard "Today")
    b_03  3333333333   birthday in 3 days        (Dashboard "This week")
    b_04  4444444444   birthday with no year     ("year unknown")
    b_06  6666666666   random birthday
    b_07  7777777777   random birthday
    b_08  8888888888   random birthday

What it sets up, so every screen has something to show:

  * Every dummy celebrates every other dummy -- EXCEPT b_08, who does not
    celebrate b_07 (one one-way relationship, so "Celebrating" and
    "Celebrates" differ for both of them).
  * YOU (default 9876543210, override with SEED_ME=+91..., or SEED_ME=none to
    leave your account alone) celebrate all six, and five of them celebrate
    you back -- b_06 does not.
  * You and b_02 also celebrate two people who are NOT on the app: one with
    no birthday at all ("No birthday yet") and one with a birthday but no
    year. Unclaimed people are the common real case, and the only ones whose
    birthday you are allowed to edit.
  * Wishes: several dummies wish b_02 (whose birthday is today) and you, and
    you wish b_02 -- so the Profile wish grid and the wish counts are not 0.

Every step goes through the same public endpoints the app uses (OTP sign-in,
claim_profile, profiles update, add_celebrations, rpc_update_person_birthday,
the wishes and celebrations tables), never direct SQL, so the rows come out
exactly as real use would make them -- triggers and guards included.

Safe to re-run. Sign-in, claiming and adding are idempotent, a random birthday
is kept once set, and a repeated wish is skipped. The TODAY and in-3-days
birthdays are recomputed from the date you run it, so re-run it on another
day to bring them back into "Today"/"This week".

Local only: refuses any URL that is not 127.0.0.1/localhost.

Run with:
    supabase start
    python3 supabase/seed_dummy_users.py
"""

import datetime as dt
import json
import os
import random
import subprocess
import sys
import urllib.error
import urllib.request

URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321")
ME = os.environ.get("SEED_ME", "+919876543210")
OTP = "123456"

DUMMIES = [2, 3, 4, 6, 7, 8]
# One-way relationships: (follower digit, followed digit) that are REMOVED
# after everyone is added. "me" stands for SEED_ME.
NOT_FOLLOWING = [(8, 7), (6, "me")]

# Not on the app: no account, so their person rows stay unclaimed. Numbers in
# the +91 90000 001xx range, nowhere in test_otp, so nobody can sign in as
# them and claim the row.
OUTSIDERS = [
    {"phone": "+919000000101", "name": "Asha (not on app)", "birthday": None},
    {"phone": "+919000000102", "name": "Ravi (not on app)",
     "birthday": {"month": 12, "day": 25, "year": None}},
]

WISHES_TO_B02 = {
    3: "Happy birthday b_02! 🎉",
    4: "Have the best day!",
    6: "Many happy returns 🎂",
    7: "Party tonight?",
    8: "HBD!! 🥳",
}
WISHES_TO_ME = {
    2: "Happy birthday Sachin!",
    3: "Wishing you a great year ahead 🎂",
    4: "Cheers to you!",
    7: "Have an amazing birthday 🎉",
}
ME_WISH_TO_B02 = "Happy birthday from me! 🎈"


def phone_of(d):
    return "+91" + str(d) * 10


def name_of(d):
    return f"b_{d:02d}"


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


def call(method, path, token=None, body=None, ok_conflict=False):
    headers = {"apikey": ANON, "content-type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if method in ("POST", "PATCH", "DELETE") and path.startswith("/rest/"):
        headers["Prefer"] = "return=representation"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, method=method,
                                 headers=headers)
    try:
        with urllib.request.urlopen(req) as res:
            text = res.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        if ok_conflict and e.code == 409:
            return None
        fail(f"{method} {path} -> {e.code}: {text}")


def sign_in(phone):
    call("POST", "/auth/v1/otp", body={"phone": phone})
    s = call("POST", "/auth/v1/verify",
             body={"phone": phone, "token": OTP, "type": "sms"})
    token = s["access_token"]
    person_id = call("POST", "/functions/v1/claim_profile", token)["person_id"]
    return {"token": token, "uid": s["user"]["id"], "person_id": person_id}


def occasion_year(month, day, today):
    """Birthday.occasionYear from lib/models/birthday.dart: the occurrence
    nearest to today, ties going to the past. Feb 29 is never generated
    here, so the leap-day rule is not needed."""
    this_year = dt.date(today.year, month, day)
    nxt = this_year if this_year >= today else dt.date(today.year + 1, month, day)
    prev = this_year if this_year <= today else dt.date(today.year - 1, month, day)
    return prev.year if (today - prev) <= (nxt - today) else nxt.year


def random_birthday(today):
    """Random, but never in the next week: those groups are reserved for
    b_02 and b_03 so the Dashboard sections stay predictable."""
    while True:
        b = dt.date(random.randint(1985, 2004), random.randint(1, 12),
                    random.randint(1, 28))
        days_until = (dt.date(today.year, b.month, b.day) - today).days % 365
        if days_until > 7:
            return {"birth_month": b.month, "birth_day": b.day,
                    "birth_year": b.year}


today = dt.date.today()
users = {}

print("Signing in and setting up profiles")
for d in DUMMIES:
    u = sign_in(phone_of(d))
    users[d] = u
    current = call(
        "GET",
        f"/rest/v1/profiles?id=eq.{u['uid']}"
        "&select=birth_month,birth_day,birth_year", u["token"])[0]

    if d == 2:
        bday = {"birth_month": today.month, "birth_day": today.day,
                "birth_year": 1990}
    elif d == 3:
        soon = today + dt.timedelta(days=3)
        bday = {"birth_month": soon.month, "birth_day": soon.day,
                "birth_year": 2001}
    elif d == 4:
        keep = current["birth_month"] and current["birth_year"] is None
        bday = ({k: current[k] for k in current} if keep else
                {**random_birthday(today), "birth_year": None})
    elif current["birth_month"]:
        bday = current
    else:
        bday = random_birthday(today)

    call("PATCH", f"/rest/v1/profiles?id=eq.{u['uid']}", u["token"], {
        **bday, "handle": name_of(d), "display_name": name_of(d),
        "city": "Jaipur",
    })
    u["birthday"] = bday
    year = bday["birth_year"] or "----"
    print(f"  {name_of(d)}  {phone_of(d)}  "
          f"born {bday['birth_day']:02d}-{bday['birth_month']:02d}-{year}")

me = None
if ME != "none":
    me = sign_in(ME)
    me_profile = call(
        "GET",
        f"/rest/v1/profiles?id=eq.{me['uid']}"
        "&select=handle,birth_month,birth_day", me["token"])[0]
    me["birthday"] = me_profile
    print(f"  you   {ME}  (@{me_profile['handle']})")

print("\nAdding people")


def add(user, contacts):
    res = call("POST", "/functions/v1/add_celebrations", user["token"],
               {"contacts": contacts})
    return {r["phone"]: r for r in res["results"]}


def contact(d):
    return {"phone": phone_of(d), "name": name_of(d)}


for d in DUMMIES:
    contacts = [contact(o) for o in DUMMIES if o != d]
    if me:
        contacts.append({"phone": ME, "name": "Sachin"})
    if d == 2:
        contacts += [{"phone": o["phone"], "name": o["name"]}
                     for o in OUTSIDERS]
    statuses = {r["status"] for r in add(users[d], contacts).values()}
    print(f"  {name_of(d)} -> {', '.join(sorted(statuses))}")

if me:
    contacts = [contact(d) for d in DUMMIES]
    contacts += [{"phone": o["phone"], "name": o["name"]} for o in OUTSIDERS]
    results = add(me, contacts)
    print(f"  you  -> {', '.join(sorted({r['status'] for r in results.values()}))}")

# Birthdays for the people who are not on the app, set the way the app's
# "Edit birthday" does. Done as b_02 so it works with SEED_ME=none too.
outsider_ids = add(users[2], [{"phone": o["phone"], "name": o["name"]}
                              for o in OUTSIDERS])
for o in OUTSIDERS:
    b = o["birthday"]
    if b is None:
        continue
    call("POST", "/rest/v1/rpc/rpc_update_person_birthday", users[2]["token"], {
        "p_person_id": outsider_ids[o["phone"]]["person_id"],
        "p_birth_month": b["month"], "p_birth_day": b["day"],
        "p_birth_year": b["year"],
    })

print("\nMaking some relationships one-way")
for follower, followed in NOT_FOLLOWING:
    if followed == "me" and not me:
        continue
    target = me["person_id"] if followed == "me" else users[followed]["person_id"]
    call("DELETE",
         f"/rest/v1/celebrations?celebrator_profile_id=eq.{users[follower]['uid']}"
         f"&person_id=eq.{target}", users[follower]["token"])
    label = "you" if followed == "me" else name_of(followed)
    print(f"  {name_of(follower)} no longer celebrates {label}")

print("\nPosting wishes")


def wish(author, subject, body):
    b = subject["birthday"]
    year = occasion_year(b["birth_month"], b["birth_day"], today)
    res = call("POST", "/rest/v1/wishes", author["token"], {
        "author_profile_id": author["uid"],
        "subject_person_id": subject["person_id"],
        "body": body,
        "occasion_year": year,
    }, ok_conflict=True)  # already wished this occasion on a previous run
    return res is not None


posted = sum(wish(users[a], users[2], body) for a, body in WISHES_TO_B02.items())
print(f"  to b_02: {posted} new")
if me:
    if me["birthday"]["birth_month"]:
        posted = sum(wish(users[a], me, body) for a, body in WISHES_TO_ME.items())
        posted += wish(me, users[2], ME_WISH_TO_B02)
        print(f"  to/from you: {posted} new")
    else:
        print("  to you: skipped -- finish your profile (birthday) first")

print(f"\nDone. Sign in with any number above and code {OTP}.")
