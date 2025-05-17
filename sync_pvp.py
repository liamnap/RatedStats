import os
import json
import asyncio
import aiohttp
import requests
import time
import collections
from pathlib import Path
from asyncio import TimeoutError, CancelledError, create_task, as_completed, shield

# custom exception to signal “please retry this char later”
class RetryCharacter(Exception):
    def __init__(self, char):
        super().__init__(f"Retry {char['name']}-{char['realm']}")
        self.char = char

# new exception: signal “rate-limited, retry later” without blocking
class RateLimitExceeded(Exception):
    pass

GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
RESET = "\033[0m"

# CONFIG
REGION = os.getenv("REGION", "eu")
API_HOST = f"{REGION}.api.blizzard.com"
API_BASE = f"https://{API_HOST}"
NAMESPACE_PROFILE = f"profile-{REGION}"
OUTFILE = Path(f"achiev/region_{REGION}.lua")
REGION_VAR = f"ACHIEVEMENTS_{REGION.upper()}"

LOCALES = {
    "us": "en_US",
    "eu": "en_GB",
    "kr": "ko_KR",
    "tw": "zh_TW"
}
LOCALE = LOCALES.get(REGION, "en_US")

class RateLimiter:
    def __init__(self, max_calls: int, period: float):
        self.max_calls = max_calls
        self.period = period
        self.calls = []

    async def acquire(self):
        now = asyncio.get_event_loop().time()
        # drop old calls outside our window
        self.calls = [t for t in self.calls if now - t < self.period]
        if len(self.calls) >= self.max_calls:
            wait = self.period - (now - self.calls[0])
            await asyncio.sleep(wait)
            now = asyncio.get_event_loop().time()
            self.calls = [t for t in self.calls if now - t < self.period]
        self.calls.append(now)

# AUTH
def get_access_token(region):
    client_id = os.environ["BLIZZARD_CLIENT_ID"]
    client_secret = os.environ["BLIZZARD_CLIENT_SECRET"]
    url = f"https://us.battle.net/oauth/token"
    resp = requests.post(
        url,
        data={"grant_type": "client_credentials"},
        auth=(client_id, client_secret)
    )
    resp.raise_for_status()
    return resp.json()["access_token"]

def get_current_pvp_season_id(region):
    url = f"https://{region}.api.blizzard.com/data/wow/pvp-season/index?namespace=dynamic-{region}&locale=en_US"
    token = get_access_token(region)
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers)
    if not resp.ok:
        raise RuntimeError(f"[FAIL] Unable to fetch PvP season index: {resp.status_code}")
    data = resp.json()
    return data["seasons"][-1]["id"]  # Last entry = latest season

from urllib.parse import urlparse

def get_available_brackets(region, season_id):
    url = f"https://{region}.api.blizzard.com/data/wow/pvp-season/{season_id}/pvp-leaderboard/index?namespace=dynamic-{region}&locale={LOCALE}"
    token = get_access_token(region)
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers)
    if not resp.ok:
        raise RuntimeError(f"[FAIL] Unable to fetch PvP leaderboard index for season {season_id}: {resp.status_code}")

    data = resp.json()
    leaderboards = data.get("leaderboards", [])

    # Bracket types to collect (based on substring or prefix logic)
    include_prefixes = ("2v2", "3v3", "rbg", "shuffle-", "blitz-")

    brackets = []
    for entry in leaderboards:
        href = entry.get("key", {}).get("href")
        if not href:
            continue
        bracket = urlparse(href).path.rstrip("/").split("/")[-1]
        if bracket.startswith(include_prefixes):
            brackets.append(bracket)

    print(f"[INFO] Valid brackets for season {season_id}: {', '.join(brackets)}")
    return brackets

PVP_SEASON_ID = get_current_pvp_season_id(REGION)
BRACKETS = get_available_brackets(REGION, PVP_SEASON_ID)

# STATIC NAMESPACE
def get_latest_static_namespace(region):
    fallback = f"static-{region}"
    try:
        token = get_access_token("us")
        headers = {"Authorization": f"Bearer {token}"}
        url = f"https://{region}.api.blizzard.com/data/wow/achievement-category/index?namespace={fallback}&locale=en_US"
        resp = requests.get(url, headers=headers)
        if not resp.ok:
            print(f"[WARN] Static namespace fetch failed for {region}, fallback to {fallback}")
            return fallback
        href = resp.json().get("_links", {}).get("self", {}).get("href", "")
        if "namespace=" in href:
            return href.split("namespace=")[-1].split("&")[0]
    except Exception as e:
        print(f"[WARN] Namespace error: {e}")
    return fallback

NAMESPACE_STATIC = get_latest_static_namespace(REGION)
print(f"[INFO] Region: {REGION}, Locale: {LOCALE}, Static NS: {NAMESPACE_STATIC}")

# CHAR LIST
def get_characters_from_leaderboards(region, headers, season_id, brackets):
    seen = {}
    for bracket in brackets:
        url = f"https://{region}.api.blizzard.com/data/wow/pvp-season/{season_id}/pvp-leaderboard/{bracket}?namespace=dynamic-{region}&locale={LOCALE}"
        r = requests.get(url, headers=headers)
        if r.status_code != 200:
            print(f"[WARN] Failed leaderboard: {bracket} - {r.status_code}")
            continue
        for entry in r.json().get("entries", []):
            c = entry.get("character")
            if not c or c["id"] in seen:
                continue

            seen[c["id"]] = {
                "id": c["id"],
                "name": c["name"],
                "realm": c["realm"]["slug"]
            }

    return seen

    # TEMP LIMIT FOR DEBUGGING
    limited = dict(list(seen.items())[:100])  # only take the first 100
    print(f"[DEBUG] Character sample size: {len(limited)}")
    return limited

#–– US needs both a per-second cap *and* a per-hour cap,
#    but we never want to actually *wait* on the hour window—
#    we want to queue any “hourly full” chars
NUM_RUNNERS = 4
if REGION == "us":
    per_sec  = RateLimiter(25  // NUM_RUNNERS, 1)      # e.g. ~6 req/sec each
    per_hour = RateLimiter(100000 // NUM_RUNNERS, 3600) # 2 500 req/hr each
else:
    per_sec  = RateLimiter(100,  1)
    per_hour = RateLimiter(1_000_000, 3600)

url_cache: dict = {}

async def fetch_with_rate_limit(session, url, headers, max_retries=5):
    # hit the cache first
    if url in url_cache:
        return url_cache[url]

    for attempt in range(1, max_retries+1):
        # block until both per-sec and per-hour allow us through
        #–– track hourly usage, but don’t block on it
        now = asyncio.get_event_loop().time()
        per_hour.calls = [t for t in per_hour.calls if now - t < per_hour.period]
        if len(per_hour.calls) >= per_hour.max_calls:
            # hit the hourly cap → queue this char rather than stall
            raise RateLimitExceeded(f"hourly cap hit on {url}")
        per_hour.calls.append(now)

        #–– throttle to per-second
        start = now
        await per_sec.acquire()
        waited = asyncio.get_event_loop().time() - start
        if waited > 1:
            print(f"{YELLOW}[RATE] waited {waited:.3f}s before calling {url}{RESET}")

        try:
            async with session.get(url, headers=headers) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    url_cache[url] = data
                    return data
                if resp.status == 429 or 500 <= resp.status < 600:
                    # immediately bail out so outer loop re-queues this char
                    raise RateLimitExceeded(f"{resp.status} on {url}")
                resp.raise_for_status()
        except (asyncio.TimeoutError) as e:
            backoff = 2 ** attempt
            print(f"{YELLOW}[WARN] timeout on {url}, retrying in {backoff}s (attempt {attempt}){RESET}")
            await asyncio.sleep(backoff)
            continue

            resp.raise_for_status()

    raise RuntimeError(f"fetch failed for {url} after {max_retries} retries")

# PVP ACHIEVEMENTS
async def get_pvp_achievements(session, headers):
    url = f"{API_BASE}/data/wow/achievement/index?namespace={NAMESPACE_STATIC}&locale=en_US"
    index = await fetch_with_rate_limit(session, url, headers)
    matches = {}

    KEYWORDS = [
        # Main Achievements
        {"type": "exact", "value": "Scout"},
        {"type": "exact", "value": "Private"},
        {"type": "exact", "value": "Grunt"},
        {"type": "exact", "value": "Corporal"},
        {"type": "exact", "value": "Sergeant"},
        {"type": "exact", "value": "Senior Sergeant"},
        {"type": "exact", "value": "Master Sergeant"},
        {"type": "exact", "value": "First Sergeant"},
        {"type": "exact", "value": "Sergeant Major"},
        {"type": "exact", "value": "Stone Guard"},
        {"type": "exact", "value": "Knight"},
        {"type": "exact", "value": "Blood Guard"},
        {"type": "exact", "value": "Knight-Lieutenant"},
        {"type": "exact", "value": "Legionnaire"},
        {"type": "exact", "value": "Knight-Captain"},
        {"type": "exact", "value": "Centurion"},
        {"type": "exact", "value": "Knight-Champion"},
        {"type": "exact", "value": "Champion"},
        {"type": "exact", "value": "Lieutenant Commander"},
        {"type": "exact", "value": "Lieutenant General"},
        {"type": "exact", "value": "Commander"},
        {"type": "exact", "value": "General"},
        {"type": "exact", "value": "Marshal"},
        {"type": "exact", "value": "Warlord"},
        {"type": "exact", "value": "Field Marshal"},
        {"type": "exact", "value": "High Warlord"},
        {"type": "exact", "value": "Grand Marshal"},

        # Rated PvP Season Tiers
        {"type": "prefix", "value": "Combatant I"},
        {"type": "prefix", "value": "Combatant II"},
        {"type": "prefix", "value": "Challenger I"},
        {"type": "prefix", "value": "Challenger II"},
        {"type": "prefix", "value": "Rival I"},
        {"type": "prefix", "value": "Rival II"},
        {"type": "prefix", "value": "Duelist"},
        {"type": "prefix", "value": "Elite"},
        {"type": "prefix", "value": "Gladiator"},
        {"type": "prefix", "value": "Legend"},

	# Special Achievements
	{"type": "prefix", "value": "Three's Company"},   			# 2700 3v3
		
	# R1 Titles
	{"type": "prefix", "value": "Hero of the Horde"},
	{"type": "prefix", "value": "Hero of the Alliance"},
	{"type": "prefix", "value": "Primal Gladiator"},      		# WoD S1
	{"type": "prefix", "value": "Wild Gladiator"},        		# WoD S2
	{"type": "prefix", "value": "Warmongering Gladiator"},		# WoD S3
	{"type": "prefix", "value": "Vindictive Gladiator"},   		# Legion S1
	{"type": "prefix", "value": "Fearless Gladiator"},      	# Legion S2
	{"type": "prefix", "value": "Cruel Gladiator"},         	# Legion S3
	{"type": "prefix", "value": "Ferocious Gladiator"},     	# Legion S4
	{"type": "prefix", "value": "Fierce Gladiator"},        	# Legion S5
	{"type": "prefix", "value": "Demonic Gladiator"},       	# Legion S6–7
	{"type": "prefix", "value": "Dread Gladiator"},     	 	# BFA S1
	{"type": "prefix", "value": "Sinister Gladiator"},      	# BFA S2
	{"type": "prefix", "value": "Notorious Gladiator"},     	# BFA S3
	{"type": "prefix", "value": "Corrupted Gladiator"},     	# BFA S4
	{"type": "prefix", "value": "Sinful Gladiator"},     		# SL S1
	{"type": "prefix", "value": "Unchained Gladiator"},     	# SL S2
	{"type": "prefix", "value": "Cosmic Gladiator"},        	# SL S3
	{"type": "prefix", "value": "Eternal Gladiator"},       	# SL S4
	{"type": "prefix", "value": "Crimson Gladiator"},       	# DF S1
	{"type": "prefix", "value": "Obsidian Gladiator"},      	# DF S2
	{"type": "prefix", "value": "Draconic Gladiator"},      	# DF S3
	{"type": "prefix", "value": "Seasoned Gladiator"},      	# DF S4
	{"type": "prefix", "value": "Forged Warlord:"},         	# TWW S1 Horde RBGB R1
	{"type": "prefix", "value": "Forged Marshal:"},         	# TWW S1 Alliance RBGB R1
	{"type": "prefix", "value": "Forged Legend:"},         		# TWW S1 SS R1
	{"type": "prefix", "value": "Forged Gladiator:"},         	# TWW S1 3v3 R1
	{"type": "prefix", "value": "Prized Warlord:"},         	# TWW S2 Horde RBGB R1
	{"type": "prefix", "value": "Prized Marshal:"},         	# TWW S2 Alliance RBGB R1
	{"type": "prefix", "value": "Prized Legend:"},         		# TWW S2 SS R1
	{"type": "prefix", "value": "Prized Gladiator:"},         	# TWW S2 3v3 R1
    ]

    for achievement in index.get("achievements", []):
        name = achievement.get("name", "")
        for kw in KEYWORDS:
            if kw["type"] == "exact" and name == kw["value"]:
                matches[achievement["id"]] = name
                break
            elif kw["type"] == "prefix" and name.startswith(kw["value"]):
                matches[achievement["id"]] = name
                break

    print(f"[DEBUG] Total PvP keyword matches: {len(matches)}")
    return matches

# CHAR ACHIEVEMENTS
async def get_character_achievements(session, headers, realm, name):
    url = f"{API_BASE}/profile/wow/character/{realm}/{name.lower()}/achievements?namespace={NAMESPACE_PROFILE}&locale={LOCALE}"
    data = await fetch_with_rate_limit(session, url, headers)
    # fetch returns {} on 429 exhaust or raises on other errors
    return data or None

# Check region files for lookup
import re

def load_existing_characters():
    if not OUTFILE.exists():
        return {}

    with OUTFILE.open("r", encoding="utf-8") as f:
        content = f.read()

    entries = re.findall(r'\{ character = "([^"]+)", guid = (\d+)(.*?)\},', content, re.DOTALL)
    characters = {}
    for char_name, guid, rest in entries:
        matches = re.findall(r'id(\d+) = (\d+), name\1 = "(.*?)"', rest)
        characters[char_name] = {
            "guid": int(guid),
            "achievements": {int(aid): name for _, aid, name in matches}
        }
    return characters

# MAIN
async def process_characters(characters):
    token = get_access_token(REGION)
    headers = {"Authorization": f"Bearer {token}"}
    existing_data = load_existing_characters()

    # 1) Fetch PvP achievements keywords
    timeout = aiohttp.ClientTimeout(total=None)  # no socket limits
    async with aiohttp.ClientSession(timeout=timeout) as session:
        pvp_achievements = await get_pvp_achievements(session, headers)
        print(f"[DEBUG] PvP keywords loaded: {len(pvp_achievements)}")

        sem = asyncio.Semaphore(10)
        total = len(characters)
        completed = 0
        last_hb = time.time()

        async def process_one(char):
            async with sem:
                name = char["name"].lower()
                realm = char["realm"].lower()
                guid = char["id"]
                key = f"{name}-{realm}"

                # fetch + retry/backoff inside fetch_with_rate_limit, but if it finally fails we raise RetryCharacter
                try:
                    data = await get_character_achievements(session, headers, realm, name)
                except (TimeoutError, aiohttp.ClientError):
                    return  # skip transient network errors this pass
                except RateLimitExceeded:
                    # hit 429/5xx → re-queue on next sweep
                    raise RetryCharacter(char)

                if not data:
                    return

                earned = data.get("achievements", [])
                if not earned:
                    return

                entry = existing_data.get(key, {"guid": guid, "achievements": {}})
                entry["guid"] = guid
                for ach in earned:
                    aid = ach["id"]
                    aname = ach.get("achievement", {}).get("name")
                    if aname and aid not in entry["achievements"]:
                        entry["achievements"][aid] = aname
                existing_data[key] = entry

        # ── multi-pass **with batching** so we never schedule 100K+ tasks at once ──
        remaining      = list(characters.values())
        # debug: show what our rate‐limits actually are
        print(f"[DEBUG] Rate limits: {per_sec.max_calls}/sec, {per_hour.max_calls}/{per_hour.period}s")
        retry_interval = 60     # seconds before each retry pass
        BATCH_SIZE     = 5000   # tweak as needed—keeps the loop sane

        while remaining:
            retry_list = []

            # process in batches of BATCH_SIZE
            total_batches = (len(remaining) + BATCH_SIZE - 1) // BATCH_SIZE
            for batch_num, offset in enumerate(range(0, len(remaining), BATCH_SIZE), start=1):
                batch = remaining[offset:offset + BATCH_SIZE]
                tasks = [create_task(process_one(c)) for c in batch]

                for finished in as_completed(tasks):
                    try:
                        await shield(finished)
                    except CancelledError:
                        continue
                    except RetryCharacter as rc:
                        retry_list.append(rc.char)
                    except Exception as e:
                        print(f"{RED}[ERROR] Character task failed: {e}{RESET}")
                        continue
                    else:
                        completed += 1
                        now = time.time()
                        if now - last_hb > 60:
                            sec_calls = len(per_sec.calls)
                            hr_calls  = len(per_hour.calls)
                            print(
                                f"[HEARTBEAT] batch {batch_num}/{total_batches} | "
                                f"{completed}/{total} done ({(completed/total*100):.1f}%), "
                                f"sec_rate={sec_calls/per_sec.period:.1f}/s ({sec_calls}/{per_sec.max_calls}), "
                                f"hourly={hr_calls}/{per_hour.max_calls}/{per_hour.period}s, "
                                f"batch_size={len(batch)}, remaining={len(remaining)}",
                                flush=True
                            )
                            last_hb = now

            if retry_list:
                print(f"{YELLOW}[INFO] Retrying {len(retry_list)} after {retry_interval}s{RESET}")
                await asyncio.sleep(retry_interval)
                remaining = retry_list
            else:
                break

    # session is closed here
    print(f"[DEBUG] Total characters in merged set: {len(existing_data)}")

    # 2) Build fingerprint & alt_map
    from itertools import combinations
    fingerprint_any = {ch: set(d["achievements"].keys()) for ch, d in existing_data.items()}
    alt_map = {ch: [] for ch in fingerprint_any}
    for a, b in combinations(fingerprint_any, 2):
        if fingerprint_any[a] & fingerprint_any[b]:
            alt_map[a].append(b)
            alt_map[b].append(a)

    # 3) Write out Lua file
    with open(OUTFILE, "w", encoding="utf-8") as f:
        f.write(f'-- File: RatedStats/achiev/region_{REGION}.lua\n')
        f.write("local achievements = {\n")
        for key in sorted(existing_data):
            obj = existing_data[key]
            alts_str = "{" + ",".join(f'"{alt}"' for alt in alt_map[key]) + "}"
            parts = [f'character="{key}"', f'alts={alts_str}', f'guid={obj["guid"]}']
            for i, (aid, aname) in enumerate(sorted(obj["achievements"].items()), 1):
                esc = aname.replace('"', '\\"')
                parts.extend([f'id{i}={aid}', f'name{i}="{esc}"'])
            f.write("    { " + ", ".join(parts) + " },\n")
        f.write("}\n\n")
        f.write(f"{REGION_VAR} = achievements\n")

# RUN
if __name__ == "__main__":
    token = get_access_token(REGION)
    headers = {"Authorization": f"Bearer {token}"}
    chars = get_characters_from_leaderboards(REGION, headers, PVP_SEASON_ID, BRACKETS)
    print(f"[FINAL DEBUG] Characters fetched: {len(chars)}")
    if chars:
#        print("[FINAL DEBUG] Characters found:", list(chars.values())[0])
    else:
        print("[FINAL DEBUG] No characters matched.")

    try:
        asyncio.run(process_characters(chars))
    except CancelledError:
        # swallow any leftover “operation was canceled” so the script exits cleanly
        print(f"{YELLOW}[WARN] Top-level run was cancelled, exiting.{RESET}")
