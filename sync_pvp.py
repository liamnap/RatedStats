import os
import json
import asyncio
import aiohttp
import requests
from pathlib import Path
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
            # TEMP: only include Advidance-Wrathbringer
#            print(f"[DEBUG] Checking character: {c['name']} - {c['realm']['slug']}")
#            if not (c["name"].lower() == "avidance" and c["realm"]["slug"].lower() == "wrathbringer"):
#                continue

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

# FETCH WRAPPER
async def fetch(session, url, headers):
    async with session.get(url, headers=headers) as r:
        if r.status != 200:
            print(f"[FAIL] {url} - {r.status}")
            return {}
        return await r.json()

# PVP ACHIEVEMENTS
async def get_pvp_achievements(session, headers):
    url = f"{API_BASE}/data/wow/achievement/index?namespace={NAMESPACE_STATIC}&locale=en_US"
    index = await fetch(session, url, headers)
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
    async with session.get(url, headers=headers) as r:
        if r.status == 404:
            # Character profile doesn't exist — likely private or inactive
            return None
        elif r.status != 200:
            print(f"[FAIL] {url} - {r.status}")
            return None
        return await r.json()

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

    timeout = aiohttp.ClientTimeout(total=15)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        pvp_achievements = await get_pvp_achievements(session, headers)
        pvp_names_set = set(pvp_achievements.values())
        print(f"[FINAL DEBUG] PvP achievement keywords loaded: {len(pvp_names_set)}")
        semaphore = asyncio.Semaphore(10)

        async def process_one(char):
            async with semaphore:
                name, realm, guid = char["name"].lower(), char["realm"].lower(), char["id"]
                char_key = f"{name}-{realm}"
                data = await get_character_achievements(session, headers, realm, name)
                if not data:
                    return
                earned = data.get("achievements", [])

                matched = []
                for a in earned:
                    aid = a["id"]
                    name = a.get("achievement", {}).get("name")
                    if not name:
                        continue
                    if name in pvp_names_set:
                        matched.append((aid, name))
                        print(f"{GREEN}[MATCH] {char_key}: {name}{RESET}")

                if not matched:
                    return

                existing = existing_data.get(char_key, {"guid": guid, "achievements": {}})
                existing["guid"] = guid
                for aid, aname in matched:
                    if aid not in existing["achievements"]:
                        existing["achievements"][aid] = aname
                existing_data[char_key] = existing

                print(f"[OK] {char_key} - {len(matched)}")

        from asyncio import as_completed

        tasks = [process_one(c) for c in characters.values()]
        results = []

        for coro in as_completed(tasks):
            try:
                await coro
            except Exception as e:
                print(f"[ERROR] Character task failed: {e}")

        print(f"[FINAL DEBUG] Total characters in merged set: {len(existing_data)}")
        with open(OUTFILE, "w", encoding="utf-8") as f:
            f.write(f'-- File: RatedStats/achiev/region_{REGION}.lua\n')
            f.write("local achievements = {\n")
            for char_key in sorted(existing_data.keys()):
                obj = existing_data[char_key]
                parts = [f'character = "{char_key}", guid = {obj["guid"]}']
                for i, (aid, name) in enumerate(sorted(obj["achievements"].items()), 1):
                    name = name.replace('"', '\\"')
                    parts.append(f'id{i} = {aid}, name{i} = "{name}"')
                lua_line = "    { " + ", ".join(parts) + " },\n"
                f.write(lua_line)
            f.write("}\n\n")
            f.write(f"{REGION_VAR} = achievements\n")

# RUN
if __name__ == "__main__":
    token = get_access_token(REGION)
    headers = {"Authorization": f"Bearer {token}"}
    chars = get_characters_from_leaderboards(REGION, headers, PVP_SEASON_ID, BRACKETS)
    print(f"[FINAL DEBUG] Characters fetched: {len(chars)}")
    if chars:
        print("[FINAL DEBUG] Characters found:", list(chars.values())[0])
    else:
        print("[FINAL DEBUG] No characters matched.")

    asyncio.run(process_characters(chars))
