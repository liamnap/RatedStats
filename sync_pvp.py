import os
import json
import asyncio
import aiohttp
import requests
from pathlib import Path

# REGION/LOCALE CONFIG
REGION = os.getenv("REGION", "eu")
API_HOST = f"{REGION}.api.blizzard.com"
API_BASE = f"https://{API_HOST}"
NAMESPACE_PROFILE = f"profile-{REGION}"
OUTFILE = Path(f"achiev/region_{REGION}.x")

LOCALES = {
    "us": "en_US",
    "eu": "en_GB",
    "kr": "ko_KR",
    "tw": "zh_TW"
}
LOCALE = LOCALES.get(REGION, "en_US")
print(f"[INFO] Running for region: {REGION} with locale: {LOCALE}")

# Known PvP category IDs
PVP_CATEGORY_IDS = [95, 165, 167, 168, 169]

# Current season and brackets to include
PVP_SEASON_ID = 38
BRACKETS = ["2v2", "3v3", "rbg", "shuffle"]

# Inline token auth
def get_access_token(region):
    client_id = os.environ["BLIZZARD_CLIENT_ID"]
    client_secret = os.environ["BLIZZARD_CLIENT_SECRET"]
    url = "https://us.battle.net/oauth/token"
    response = requests.post(
        url,
        data={"grant_type": "client_credentials"},
        auth=(client_id, client_secret)
    )
    response.raise_for_status()
    return response.json()["access_token"]

def get_latest_static_namespace(region):
    # fallback to basic if the call fails
    default = f"{REGION}"
    token = get_access_token("us")
    headers = {"Authorization": f"Bearer {token}"}

    index_url = f"https://{region}.api.blizzard.com/data/wow/achievement-category/index?namespace=static-{region}&locale=en_US"
    try:
        resp = requests.get(index_url, headers=headers)
        resp.raise_for_status()
        namespace = resp.json().get("_links", {}).get("self", {}).get("href", "")
        # Extract versioned namespace
        if "namespace=" in namespace:
            return namespace.split("namespace=")[-1].split("&")[0]
    except Exception as e:
        print(f"[WARN] Could not fetch latest static namespace: {e}")
    return default
NAMESPACE_STATIC = f"static-{get_latest_static_namespace(REGION)}"
print(f"[INFO] Resolved static namespace: {NAMESPACE_STATIC}")

# Fetch character list from PvP leaderboard
def get_characters_from_leaderboards(region, headers, season_id, brackets):
    characters_by_guid = {}

    for bracket in brackets:
        url = f"https://{region}.api.blizzard.com/data/wow/pvp-season/{season_id}/pvp-leaderboard/{bracket}?namespace=dynamic-{region}&locale={LOCALE}"
        response = requests.get(url, headers=headers)
        if response.status_code != 200:
            print(f"Failed leaderboard fetch: {url} - {response.status_code}")
            continue

        data = response.json()
        for entry in data.get("entries", []):
            char = entry.get("character")
            if not char:
                continue

            char_id = char["id"]
            realm = char["realm"]["slug"]
            name = char["name"]

            if char_id not in characters_by_guid:
                characters_by_guid[char_id] = {
                    "id": char_id,
                    "name": name,
                    "realm": realm
                }

    return characters_by_guid  # keyed by guid

# Async fetch helper
async def fetch(session, url, headers):
    async with session.get(url, headers=headers) as resp:
        if resp.status != 200:
            print(f"Failed: {url} - {resp.status}")
            return {}
        return await resp.json()

# Get PvP achievements
async def get_pvp_achievements(session, headers):
    achievements = {}
    for category_id in PVP_CATEGORY_IDS:
        url = f"{API_BASE}/data/wow/achievement-category/{category_id}?namespace={NAMESPACE_STATIC}&locale={LOCALE}"
        data = await fetch(session, url, headers)

        if not data or "achievements" not in data:
            print(f"[WARN] Missing or invalid category {category_id} in region {REGION}")
            continue

        if not data:  # ✅ ADD THIS CHECK
            print(f"[SKIP] Category {category_id} returned no data")
            continue

        for ach in data.get("achievements", []):
            achievements[ach["id"]] = ach["name"]
    return achievements

# Get a character’s achievements
async def get_character_achievements(session, headers, realm, name):
    url = f"{API_BASE}/profile/wow/character/{realm}/{name.lower()}/achievements?namespace={NAMESPACE_PROFILE}&locale={LOCALE}"
    return await fetch(session, url, headers)

# Main logic
async def process_characters(characters_by_guid):
    token = get_access_token(REGION)
    headers = {"Authorization": f"Bearer {token}"}

    async with aiohttp.ClientSession() as session:
        pvp_achievements = await get_pvp_achievements(session, headers)
        semaphore = asyncio.Semaphore(10)

        async def process_one(char):
            async with semaphore:
                name = char["name"].lower()
                realm = char["realm"].lower()
                guid = char["id"]
                char_key = f"{name}-{realm}"

                data = await get_character_achievements(session, headers, realm, name)
                if not data:
                    print(f"[SKIP] {char_key} - no data (possibly 404)")
                    return None

                earned = data.get("achievements", [])
                earned_pvp = [
                    (ach["id"], pvp_achievements[ach["id"]])
                    for ach in earned
                    if ach["id"] in pvp_achievements
                ]

                if not earned_pvp:
                    print(f"[NO PVP] {char_key} - has no PvP achievements")
                    return None

                entry = {
                    "character": char_key,
                    "guid": guid
                }
                for idx, (aid, aname) in enumerate(earned_pvp, 1):
                    entry[f"id{idx}"] = aid
                    entry[f"name{idx}"] = aname

                print(f"Stored: {char_key} with {len(earned_pvp)} PvP achievements")
                return json.dumps(entry, separators=(",", ":"))

        tasks = [process_one(char) for char in characters_by_guid.values()]
        results = await asyncio.gather(*tasks)

        # Filter out None results
        filtered_results = [line for line in results if line]

        # Sort by character name
        sorted_results = sorted(filtered_results, key=lambda line: json.loads(line)["character"])

        # Write to file
        with open(OUTFILE, "w") as f:
            for line in sorted_results:
                f.write(line + "\n")

# Entry point
if __name__ == "__main__":
    token = get_access_token(REGION)
    headers = { "Authorization": f"Bearer {token}" }

    characters_by_guid = get_characters_from_leaderboards(
        region=REGION,
        headers=headers,
        season_id=PVP_SEASON_ID,
        brackets=BRACKETS
    )

    asyncio.run(process_characters(characters_by_guid))
