import os
import json
import sqlite3
import tempfile
import asyncio
import aiohttp
import requests
import time
import datetime
import collections
import gc
import re
from pathlib import Path
from asyncio import TimeoutError, CancelledError, create_task, as_completed, shield
try:
    import psutil            # for CPU / RAM telemetry
except ImportError:
    psutil = None

# --------------------------------------------------------------------------
# Record when the run began (monotonic avoids wall-clock jumps)
UTC = datetime.timezone.utc
start_time = time.time()
#---------------------------------------------------------------------------

# --------------------------------------------------------------------------
# Helper – pretty-print an integer number of seconds as
# “2y 5w 3d 4h 17s”, omitting zero units.
# --------------------------------------------------------------------------
def _fmt_duration(sec: int) -> str:
    if sec <= 0:
        return "0s"
    parts = []
    yr,  sec = divmod(sec, 31_557_600)     # 365.25 d
    if yr:  parts.append(f"{yr}y")
    wk,  sec = divmod(sec, 604_800)        # 7 d
    if wk:  parts.append(f"{wk}w")
    day, sec = divmod(sec, 86_400)
    if day: parts.append(f"{day}d")
    hr,  sec = divmod(sec, 3_600)
    if hr:  parts.append(f"{hr}h")
    mn,  sec = divmod(sec, 60)        
    if mn:  parts.append(f"{mn}m")    
    if sec: parts.append(f"{sec}s")
    return " ".join(parts)

# --------------------------------------------------------------------------
#   CALL COUNTERS
# --------------------------------------------------------------------------
CALLS_DONE   = 0                     # incremented every time we really hit the API
TOTAL_CALLS  = None                  # set once we know how many calls the run will need
# 429 tracker
HTTP_429_QUEUED = 0

# keep timestamps of the last 60 s for a rolling average
from collections import deque
CALL_TIMES: deque[float] = deque()   # append(time.time()) in _bump_calls()

# helper: increment safely
def _bump_calls():
    global CALLS_DONE
    CALLS_DONE += 1
    now = time.time()
    CALL_TIMES.append(now)
    # purge anything older than 60 s
    while CALL_TIMES and now - CALL_TIMES[0] > 60:
        CALL_TIMES.popleft()

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
            seen[c["id"]] = {"id": c["id"], "name": c["name"], "realm": c["realm"]["slug"]}
    return seen

# --- Rate-limit config
NUM_RUNNERS = 4
per_sec  = RateLimiter(100, 1)
per_hour = RateLimiter(1_500_000, 3600)
url_cache: dict[str, dict] = {}

async def fetch_with_rate_limit(session, url, headers, max_retries: int = 5):
    cacheable = ("profile/wow/character" not in url and "oauth" not in url)
    if cacheable and url in url_cache:
        return url_cache[url]
    await asyncio.gather(per_sec.acquire(), per_hour.acquire())
    for attempt in range(1, max_retries + 1):
        try:
            async with session.get(url, headers=headers) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    if cacheable:
                        url_cache[url] = data
                    _bump_calls()
                    return data
                if resp.status == 429:
                    global HTTP_429_QUEUED
                    HTTP_429_QUEUED += 1
                    raise RateLimitExceeded("429 Too Many Requests")
                if 500 <= resp.status < 600:
                    raise RateLimitExceeded(f"{resp.status} on {url}")
                resp.raise_for_status()
        except asyncio.TimeoutError:
            backoff = 2 ** attempt
            print(f"{YELLOW}[WARN] timeout on {url}, retrying in {backoff}s (attempt {attempt}){RESET}")
            await asyncio.sleep(backoff)
    raise RuntimeError(f"fetch failed for {url} after {max_retries} retries")

# PVP ACHIEVEMENTS
async def get_pvp_achievements(session, headers):
    url = f"{API_BASE}/data/wow/achievement/index?namespace={NAMESPACE_STATIC}&locale=en_US"
    index = await fetch_with_rate_limit(session, url, headers)
    matches = {}
    KEYWORDS = [ ... ]  # truncated for brevity
    for achievement in index.get("achievements", []):
        name = achievement.get("name", "")
        for kw in KEYWORDS:
            if (kw["type"] == "exact" and name == kw["value"]) or \
               (kw["type"] == "prefix" and name.startswith(kw["value"])):
                matches[achievement["id"]] = name
                break
    print(f"[DEBUG] Total PvP keyword matches: {len(matches)}")
    return matches

# Disk-backed per-character store
DB_PATH = Path(tempfile.gettempdir()) / f"achiev_{REGION}.db"
db = sqlite3.connect(DB_PATH)
db.execute("""
CREATE TABLE IF NOT EXISTS char_data (
    key      TEXT PRIMARY KEY,
    guid     INTEGER,
    ach_json TEXT
)
"""
)
db.commit()

def db_upsert(key: str, guid: int, ach_dict: dict[int, str]) -> None:
    db.execute(
        "INSERT OR REPLACE INTO char_data (key, guid, ach_json) VALUES (?,?,?)",
        (key, guid, json.dumps(ach_dict, separators=(',', ':')))
    )
def db_iter_rows():
    cur = db.execute("SELECT key, guid, ach_json FROM char_data ORDER BY key")
    for key, guid, ach_json in cur:
        yield key, guid, json.loads(ach_json)

# --------------------------------------------------------------------------
# Parse existing Lua into SQLite + return char map
# --------------------------------------------------------------------------
def seed_db_from_lua(lua_path: Path) -> dict[str, dict]:
    if not lua_path.exists():
        return {}
    txt = lua_path.read_text(encoding="utf-8")
    row_rx = re.compile(r'\{[^{]*?character\s*=\s*"([^"]+)"[^}]*?\}', re.S)
    ach_rx = re.compile(r'id(\d+)\s*=\s*(\d+),\s*name\1\s*=\s*"([^"]+)"')
    guid_rx = re.compile(r'guid\s*=\s*(\d+)')

    rows: dict[str, dict] = {}
    for row in row_rx.finditer(txt):
        block = row.group(0)
        char_key = row.group(1)
        guid_m = guid_rx.search(block)
        if not guid_m:
            continue
        guid = int(guid_m.group(1))
        ach_dict = {int(aid): name for _, aid, name in ach_rx.findall(block)}
        name, realm = char_key.split("-", 1)  # <-- NEW
        rows[char_key] = {"id": guid, "name": name, "realm": realm}  # <-- NEW
        db_upsert(char_key, guid, ach_dict)
    return rows

# initial seeding (no return)
seed_db_from_lua(OUTFILE)

# MAIN
async def process_characters(characters):
    token = get_access_token(REGION)
    headers = {"Authorization": f"Bearer {token}"}
    timeout = aiohttp.ClientTimeout(total=None)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        global TOTAL_CALLS
        TOTAL_CALLS = len(characters) + 1
        pvp_achievements = await get_pvp_achievements(session, headers)
        print(f"[DEBUG] PvP keywords loaded: {len(pvp_achievements)}")

        SEM_CAPACITY = 10
        sem = asyncio.Semaphore(SEM_CAPACITY)
        total = len(characters)
        completed = 0
        last_hb = time.time()

        async def process_one(char):
            async with sem:
                name = char["name"].lower()
                realm = char["realm"].lower()
                guid = char["id"]
                key = f"{name}-{realm}"
                try:
                    data = await get_character_achievements(session, headers, realm, name)
                except (TimeoutError, aiohttp.ClientError):
                    return
                except RateLimitExceeded:
                    raise RetryCharacter(char)
                if not data:
                    return
                earned = data.get("achievements", [])
                ach_dict = {ach["id"]: ach["achievement"]["name"]
                            for ach in earned if ach["id"] in pvp_achievements}
                if ach_dict:
                    db_upsert(key, guid, ach_dict)

        remaining = list(characters.values())
        print(f"[DEBUG] Rate limits: {per_sec.max_calls}/sec, {per_hour.max_calls}/{per_hour.period}s")
        retry_interval = 60
        BATCH_SIZE = 5_000  # reduced for RAM control

        while remaining:
            retry_list = []
            total_batches = (len(remaining) + BATCH_SIZE - 1) // BATCH_SIZE
            for batch_num, offset in enumerate(range(0, len(remaining), BATCH_SIZE), start=1):
                batch = remaining[offset:offset + BATCH_SIZE]
                tasks = [create_task(process_one(c)) for c in batch]
                for finished in as_completed(tasks):
                    try:
                        await shield(finished)
                    except RetryCharacter as rc:
                        retry_list.append(rc.char)
                    except Exception as e:
                        print(f"{RED}[ERROR] {e}{RESET}")
                    else:
                        completed += 1
                        now = time.time()
                        if now - last_hb > 10:
                            url_cache.clear()
                            gc.collect()
                            # ... heartbeat omitted for brevity ...
                            last_hb = now
            url_cache.clear()
            if retry_list:
                print(f"{YELLOW}[INFO] Retrying {len(retry_list)} after {retry_interval}s{RESET}")
                await asyncio.sleep(retry_interval)
                remaining = retry_list
            else:
                break

        # build alt map
        from itertools import combinations
        fingerprints = {k: set(m.keys()) for k, _, m in db_iter_rows()}
        alt_map = {k: [] for k in fingerprints}
        for a, b in combinations(fingerprints, 2):
            if fingerprints[a] & fingerprints[b]:
                alt_map[a].append(b)
                alt_map[b].append(a)

    # write Lua
    OUTFILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTFILE, "w", encoding="utf-8") as f:
        f.write(f"-- File: RatedStats/achiev/region_{REGION}.lua\n")
        f.write("local achievements = {\n")
        for key, guid, ach_map in db_iter_rows():
            alts = alt_map.get(key, [])
            alts_str = "{" + ",".join(f'"{alt}"' for alt in alts) + "}"
            parts = [f'character="{key}"', f'alts={alts_str}', f'guid={guid}']
            for i, (aid, name) in enumerate(sorted(ach_map.items()), 1):
                esc = name.replace('"', '\\"')
                parts.extend([f'id{i}={aid}', f'name{i}="{esc}"'])
            f.write("    { " + ", ".join(parts) + " },\n")
        f.write("}\n\n")
        f.write(f"{REGION_VAR} = achievements\n")
    db.close()

# RUN
if __name__ == "__main__":
    token = get_access_token(REGION)
    headers = {"Authorization": f"Bearer {token}"}
    chars = get_characters_from_leaderboards(REGION, headers, PVP_SEASON_ID, BRACKETS)
    old_chars = seed_db_from_lua(OUTFILE)
    chars.update(old_chars)
    print(f"[FINAL DEBUG] Total chars this run: {len(chars)}")
    asyncio.run(process_characters(chars))
