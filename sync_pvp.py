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
        # token-bucket enforcement
        self.capacity  = max_calls            # bucket size
        self.tokens    = 0                    # current tokens
        self.fill_rate = max_calls / period   # tokens per second
        self.timestamp = time.monotonic()     # last refill check

        # serialize acquires so bucket logic is safe under concurrency
        self._lock = asyncio.Lock()

        # metrics (for your existing heartbeat debug)
        self.max_calls = max_calls            # alias for capacity
        self.period    = period               # window length (s)
        self.calls     = []                   # timestamp list for rolling-window rate

    async def acquire(self):
        async with self._lock:
            # refill token bucket
            now     = time.monotonic()
            elapsed = now - self.timestamp
            self.timestamp = now
            self.tokens    = min(self.capacity, self.tokens + elapsed * self.fill_rate)

            # if empty, wait exactly until 1 token is refilled
            if self.tokens < 1:
                wait_time = (1 - self.tokens) / self.fill_rate
                await asyncio.sleep(wait_time)
                now            = time.monotonic()
                self.timestamp = now
                self.tokens    = 1

            # consume the token
            self.tokens -= 1

            # update your sliding-window metric for heartbeats
            self.calls = [t for t in self.calls if now - t < self.period]
            self.calls.append(now)

# AUTH
def get_access_token(region):
    if region == "eu" and os.getenv("BLIZZARD_CLIENT_ID_EU") and os.getenv("BLIZZARD_CLIENT_SECRET_EU"):
        client_id = os.getenv("BLIZZARD_CLIENT_ID_EU")
        client_secret = os.getenv("BLIZZARD_CLIENT_SECRET_EU")
    elif region == "us" and os.getenv("BLIZZARD_CLIENT_ID_US") and os.getenv("BLIZZARD_CLIENT_SECRET_US"):
        client_id = os.getenv("BLIZZARD_CLIENT_ID_US")
        client_secret = os.getenv("BLIZZARD_CLIENT_SECRET_US")
    else:
        client_id = os.getenv("BLIZZARD_CLIENT_ID")
        client_secret = os.getenv("BLIZZARD_CLIENT_SECRET")

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

# Show which API credentials are active
if REGION == "eu" and os.getenv("BLIZZARD_CLIENT_ID_EU"):
    api_used = os.getenv("BLIZZARD_CLIENT_ID_EU")
elif REGION == "us" and os.getenv("BLIZZARD_CLIENT_ID_US"):
    api_used = os.getenv("BLIZZARD_CLIENT_ID_US")
else:
    api_used = os.getenv("BLIZZARD_CLIENT_ID")

print(f"[DEBUG] Using API credentials for {REGION}: …{api_used[-6:]}")

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

# --- Rate-limit configuration -------------------------------------------
# Battle.net hard caps at unknown req/s *per public IP* and unknown req/day.
# Four runners share the same IP, so stay conservative.
REGION_CAP = 9 if REGION in ("us", "eu") else 100
per_sec = RateLimiter(REGION_CAP, 1)
SEM_CAPACITY = REGION_CAP  # or lower if you like

per_hour = RateLimiter(36_000, 3600)
url_cache: dict[str, dict] = {}                   # simple in-memory GET cache
# ------------------------------------------------------------------------

async def fetch_with_rate_limit(session, url, headers, max_retries: int = 5):
    # --- cache only static endpoints ------------------------------------
    cacheable = (
        "profile/wow/character" not in url           # character calls
        and "oauth"             not in url           # token
    )

    if cacheable and url in url_cache:
        return url_cache[url]
    # --------------------------------------------------------------------

    # throttle *before* we actually hit the network
    await per_sec.acquire()
    await per_hour.acquire()

    for attempt in range(1, max_retries + 1):
        try:
            async with session.get(url, headers=headers) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    if cacheable:
                        url_cache[url] = data        # store only if wanted
                    _bump_calls()
                    return data
                if resp.status == 429:
                    # track & re-queue on next sweep
                    global HTTP_429_QUEUED
                    HTTP_429_QUEUED += 1
                    raise RateLimitExceeded("429 Too Many Requests")
                if 500 <= resp.status < 600:
                    raise RateLimitExceeded(f"{resp.status} on {url}")
                resp.raise_for_status()

        except asyncio.TimeoutError:
            backoff = 2 ** attempt
            print(f"{YELLOW}[WARN] timeout on {url}, retrying in {backoff}s "
                  f"(attempt {attempt}){RESET}")
            await asyncio.sleep(backoff)
            continue

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
        {"type": "prefix", "value": "Elite:"},
        {"type": "prefix", "value": "Gladiator:"},
        {"type": "prefix", "value": "Legend:"},

    	# Special Achievements
	    {"type": "prefix", "value": "Three's Company: 2700"},   			# 2700 3v3
		
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

# --------------------------------------------------------------------------
#  Disk-backed per-character store (SQLite, lives in /tmp)
# --------------------------------------------------------------------------
DB_PATH = Path(tempfile.gettempdir()) / f"achiev_{REGION}.db"
db = sqlite3.connect(DB_PATH)
db.execute("""
    CREATE TABLE IF NOT EXISTS char_data (
        key      TEXT PRIMARY KEY,
        guid     INTEGER,
        ach_json TEXT
    )
""")

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

# --- after the CREATE TABLE … db.commit() lines --------------------------
def seed_db_from_lua(lua_path: Path) -> dict[str, dict]:
    """Parse an existing region_*.lua and insert its rows into SQLite,
    returning a dict of { char_key: { id, name, realm } } for merging."""
    rows: dict[str, dict] = {}
    if not lua_path.exists():
        return rows

    txt = lua_path.read_text(encoding="utf-8")
    row_rx  = re.compile(r'\{[^{]*?character\s*=\s*"([^"]+)"[^}]*?\}', re.S)
    ach_rx  = re.compile(r'id(\d+)\s*=\s*(\d+),\s*name\1\s*=\s*"([^"]+)"')
    guid_rx = re.compile(r'guid\s*=\s*(\d+)')

    for row in row_rx.finditer(txt):
        block    = row.group(0)
        char_key = row.group(1)
        guid_m   = guid_rx.search(block)
        if not guid_m:
            continue
        guid     = int(guid_m.group(1))
        ach_dict = {int(aid): name for _, aid, name in ach_rx.findall(block)}
        # upsert into SQLite as before
        db_upsert(char_key, guid, ach_dict)

        # build the return map
        name, realm = char_key.split("-", 1)
        rows[char_key] = {"id": guid, "name": name, "realm": realm}

    db.commit()
    return rows

# MAIN
async def process_characters(characters, leaderboard_keys):
    global HTTP_429_QUEUED
    token = get_access_token(REGION)
    headers = {"Authorization": f"Bearer {token}"}
    # ── DEBUG: count how many db_upserts actually happen
    inserted_count = 0

    # 1) Fetch PvP achievements keywords
    timeout = aiohttp.ClientTimeout(total=5)  # no socket limits
    async with aiohttp.ClientSession(timeout=timeout) as session:
        global TOTAL_CALLS
        TOTAL_CALLS = len(characters) + 1
        pvp_achievements = await get_pvp_achievements(session, headers)
        print(f"[DEBUG] PvP keywords loaded: {len(pvp_achievements)}")

        # === reset rate‐limiter bucket so we don't get an initial flood ===
        now = asyncio.get_event_loop().time()
        per_sec.tokens    = 0
        per_sec.timestamp = now
        per_sec.calls.clear()
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

            # (A) capture id *and* completion timestamp for true fingerprinting
            ach_dict = {}
            for ach in earned:
                aid = ach["id"]
                if aid not in pvp_achievements:
                    continue
                # the JSON field is "completed_timestamp"
                ts = ach.get("completed_timestamp")
                if ts is None and aid != 9494:
                    # DEBUG: show you exactly what's coming back
                    print(f"{YELLOW}[DEBUG] no completed_timestamp for {key} ach {aid}{RESET}")
                ach_dict[aid] = {"name": ach["achievement"]["name"], "ts": ts}

                db_upsert(key, guid, ach_dict)
                nonlocal inserted_count
                inserted_count += 1

        # ── multi-pass **with batching** so we never schedule 100K+ tasks at once ──
        remaining      = list(characters.values())
        # debug: show what our rate‐limits actually are
        print(f"[DEBUG] Rate limits: {per_sec.max_calls}/sec, {per_hour.max_calls}/{per_hour.period}s")
        retry_interval = 10     # seconds before each retry pass
        BATCH_SIZE     = 2500   # tweak as needed—keeps the loop sane
        # remember how many 429s we’d seen at the last backoff
        prev_429_count = 0

        while remaining:
            # per-pass retry bucket
            retry_dict: dict[str, dict] = {}

            # process in batches of BATCH_SIZE, backing off whenever 1k new 429s arrive
            total_batches = (len(remaining) + BATCH_SIZE - 1) // BATCH_SIZE
            for batch_num, offset in enumerate(range(0, len(remaining), BATCH_SIZE), start=1):
                # how many new 429s since last pause?
                delta = HTTP_429_QUEUED - prev_429_count
                if delta >= 1000:
                    cur_time = time.strftime("%H:%M:%S", time.localtime())
                    print(f"[{cur_time}] {YELLOW}[INFO] {delta} new 429s queued; pausing for 5 seconds{RESET}", flush=True)
                    await asyncio.sleep(5)              # let in-flight finish then sleep
                    prev_429_count = HTTP_429_QUEUED      # checkpoint here
                
                batch = remaining[offset:offset + BATCH_SIZE]

                # ◀️ schedule these before awaiting
                tasks = [create_task(process_one(c)) for c in batch]
		    
                for finished in as_completed(tasks):
                    try:
                        await shield(finished)
                    except CancelledError:
                        continue
                    except RetryCharacter as rc:
                        # dedupe by key ("name-realm")
                        key = f"{rc.char['name']}-{rc.char['realm']}"
                        retry_dict[key] = rc.char
                    except Exception as e:
                        print(f"{RED}[ERROR] Character task failed: {e}{RESET}")
                        continue
                    else:
                        completed += 1
                        now = time.time()
                        if now - last_hb > 10:
                            url_cache.clear()          # drop JSON blobs
                            gc.collect()               # force-GC, keeps the runner tidy
                            ts = time.strftime("%H:%M:%S", time.localtime(now)) 
                            inflight = SEM_CAPACITY - sem._value
                            waiters  = len(sem._waiters)
                            backlog  = len(remaining)

                            # runner telemetry (psutil may be missing)
                            cpu_pct = f"{psutil.cpu_percent():.0f}%" if psutil else "n/a"
                            ram_pct = f"{psutil.virtual_memory().percent:.0f}%" if psutil else "n/a"

                            sec_calls = len(per_sec.calls)          # in-flight 1-s bucket
                            hr_calls  = len(per_hour.calls)         # running 1-h bucket
                            avg_60s   = len(CALL_TIMES) / 60        # rolling 60-s average

                            # ── ETA maths ─────────────────────────────
                            elapsed   = now - start_time            # seconds so far
                            remaining_left  = total - completed
                            remaining_calls = TOTAL_CALLS - CALLS_DONE if TOTAL_CALLS else None
                            eta_sec = (
                                elapsed / CALLS_DONE * remaining_calls
                            ) if CALLS_DONE and remaining_calls is not None else None

                            # ── robust ETA ──
                            TEN_YEARS_SEC = 315_576_000                    # 10 years
                            if eta_sec is None or eta_sec > TEN_YEARS_SEC:
                                eta_when = "calculating…"
                            else:
                                try:
                                    eta_when_dt = (
                                        datetime.datetime.now(UTC)
                                        + datetime.timedelta(seconds=int(eta_sec))
                                    )
                                    # show “YYYY-MM-DD HH:MMZ”
                                    eta_when = eta_when_dt.strftime("%Y-%m-%d %H:%MZ")
                                except OverflowError:
                                    eta_when = ">9999-01-01"

                            ts_now = time.strftime("%H:%M:%S")
                            if ts_now.startswith(ts_now[:2] + ":00:"):
                                print(f"[{ts_now}] [INFO] Start of new hour — sleeping 1 minutes to prevent hitting API hourly cap.", flush=True)
                                await asyncio.sleep(60)

                            print(
                                f"[{ts}] [HEARTBEAT] batch {batch_num}/{total_batches} | "
                                f"{completed}/{total} done ({(completed/total*100):.1f}%), "
                                f"sec_rate={sec_calls/per_sec.period:.1f}/s "
                                f"avg60={avg_60s:.1f}/s "
                                f"cap={per_sec.max_calls}/s, "                                
                				f"hourly={hr_calls}/{per_hour.max_calls}/{per_hour.period}s, "
                                f"batch_size={len(batch)}, remaining={remaining_left}, "
                                f"remaining_calls={remaining_calls}, "
                                f"elapsed={_fmt_duration(int(elapsed))}, "
                                f"ETA={_fmt_duration(int(eta_sec)) if eta_sec is not None else '–'} "
                                f"(~{eta_when}), "
                                f"inflight={inflight}, waiters={waiters}, backlog={backlog}, "
                                f"429_queued={HTTP_429_QUEUED}, "
                                f"cpu={cpu_pct}, ram={ram_pct}",
                                flush=True
                            )
                            last_hb = now

            # ── drop cached JSON to keep RAM flat ──
            url_cache.clear()

            if retry_dict:
                print(f"{YELLOW}[INFO] Retrying {len(retry_dict)} unique chars after {retry_interval}s{RESET}")
                await asyncio.sleep(retry_interval)
                remaining = list(retry_dict.values())
            else:
                break

        db.commit()
        # ── DEBUG: did our upserts match the table size?
        print(f"[DEBUG] inserted_count={inserted_count}")
        row_count = sum(1 for _ in db_iter_rows())
        print(f"[DEBUG] SQLite rows={row_count}")

        # -------------------------------------------------
        # 2)  Build a simple alt map from the rows in SQLite
        # -------------------------------------------------
        from itertools import combinations

        # build fingerprint as (id, timestamp) pairs
        fingerprints = {}
        for key, guid, ach_map in db_iter_rows():
            pts = set()
            for aid, info in ach_map.items():
                ts = info.get("ts")
                if ts is not None:
                    pts.add((aid, ts))
            fingerprints[key] = pts

        alt_map = {k: [] for k in fingerprints}
        for a, b in combinations(fingerprints, 2):
            # now only match when they share the same id *and* timestamp
            shared = fingerprints[a] & fingerprints[b]
            if len(shared) < 5:  # you can raise this threshold if needed
                continue
            alt_map[a].append(b)
            alt_map[b].append(a)

        # ── DEBUG: inspect alt_map right after building it
        total_keys = len(alt_map)
        linked_keys = sum(1 for links in alt_map.values() if links)
        print(f"[DEBUG] alt_map keys={total_keys}, with_links={linked_keys}")
        for k, links in list(alt_map.items())[:3]:
            print(f"[DEBUG] sample alt_map[{k!r}] → {len(links)} links")

        # ── DEBUG: show a few sample alt_map entries
        samples = list(alt_map.items())[:3]
        for key, links in samples:
            print(f"[DEBUG] alt_map sample {key!r} → {len(links)} alts")

    # ── now break into connected components, pick the first as “root” ──
    visited = set()
    groups = []
    for key in sorted(alt_map):
        if key in visited:
            continue
        # flood‐fill this component
        comp = {key}
        stack = [key]
        while stack:
            u = stack.pop()
            for v in alt_map[u]:
                if v not in comp:
                    comp.add(v)
                    stack.append(v)
        visited |= comp
        groups.append(sorted(comp))     # sorted list of all chars in this group

    # ── DEBUG: analyze your groups
    from collections import Counter
    sizes = [len(c) for c in groups]
    print(f"[DEBUG] total_groups={len(groups)}, size_counts={Counter(sizes)}")
    # log top 3 largest components
    largest = sorted(groups, key=len, reverse=True)[:3]
    for i, comp in enumerate(largest, 1):
        print(f"[DEBUG] group#{i} size={len(comp)}, sample={comp[:5]}")
	
    # session is closed here
    # ── DEBUG: how many components, and total chars across them
    total_group_members = sum(len(c) for c in groups)
    print(f"[DEBUG] group_roots={len(groups)}, total_group_members={total_group_members}")

    # ── DEBUG: sanity checks before Lua write
    row_count = sum(1 for _ in db_iter_rows())
    print(f"[DEBUG] SQLite has {row_count} character rows")
    print("[DEBUG] Writing Lua file…")

    # build a lookup so we can pull guid + ach_map by key
    rows_map = {
       key: (guid, ach_map)
        for key, guid, ach_map in db_iter_rows()
    }
    # DEBUG: now that rows_map exists, inspect it
    print(f"[DEBUG] rows_map entries={len(rows_map)}, sample keys={list(rows_map)[:5]}")

    # make sure achiev/ exists no matter which branch we're on
    OUTFILE.parent.mkdir(parents=True, exist_ok=True)

    # build a lookup so we can pull guid + ach_map by key
    rows_map = { key: (guid, ach_map)
                 for key, guid, ach_map in db_iter_rows() }

    # write out only one “root” per connected component,
    # choosing roots that actually came from the leaderboard
    with open(OUTFILE, "w", encoding="utf-8") as f:
        f.write(f'-- File: RatedStats/achiev/region_{REGION}.lua\n')
        f.write("local achievements = {\n")

        for comp in groups:
            # DEBUG: each group we’re about to write
            print(f"[DEBUG] group of size={len(comp)}, leaders={len([m for m in comp if m in leaderboard_keys])}")

            real_leaders = [m for m in comp if m in leaderboard_keys]
            if not real_leaders:
                continue

            root = real_leaders[0]
            # DEBUG: writing the root entry for this component
            print(f"[DEBUG] writing character={root}")
            alts = [m for m in comp if m != root]

            # DEBUG: root we’ll write
            print(f"[DEBUG] writing entry for root {root}")

            guid, ach_map = rows_map[root]
            alts_str = "{" + ",".join(f'"{alt}"' for alt in alts) + "}"

            parts = [
                f'character="{root}"',
                f'alts={alts_str}',
                f'guid={guid}'
            ]
            for i, (aid, info) in enumerate(sorted(ach_map.items()), start=1):
                name = info["name"]
                esc  = name.replace('"', '\\"')
                parts.extend([f"id{i}={aid}", f'name{i}="{esc}"'])

            f.write("    { " + ", ".join(parts) + " },\n")

        f.write("}\n\n")
        f.write(f"{REGION_VAR} = achievements\n")

    # ── DEBUG: confirm how many “root” entries we just emitted
    print(f"[DEBUG] Emitted {len(groups)} entries into region_{REGION}.lua")

    db.close()

# RUN
if __name__ == "__main__":
    old_chars = seed_db_from_lua(OUTFILE)
    print(f"[DEBUG] seed_db_from_lua loaded {len(old_chars)} prior entries")
    token = get_access_token(REGION)
    headers = {"Authorization": f"Bearer {token}"}
    # fetch raw API characters
    api_chars = get_characters_from_leaderboards(REGION, headers, PVP_SEASON_ID, BRACKETS)
    # normalize into the same lower-case name-realm key that we use in db_upsert()
    leaderboard_keys = {
        f"{c['name'].lower()}-{c['realm'].lower()}"
        for c in api_chars.values()
    }
    # merge API chars with any seeded-from-lua chars
    chars = { **api_chars, **old_chars }
    print(f"[FINAL DEBUG] Total chars this run: {len(chars)}")
    if chars:
         pass
#        print("[FINAL DEBUG] Characters found:", list(chars.values())[0])
    else:
        print("[FINAL DEBUG] No characters matched.")

    try:
        asyncio.run(process_characters(chars, leaderboard_keys))
    except CancelledError:
        # swallow any leftover “operation was canceled” so the script exits cleanly
        print(f"{YELLOW}[WARN] Top-level run was cancelled, exiting.{RESET}")
