import os
import json
import asyncio
import aiohttp
import requests
from pathlib import Path

# REGION/LOCALE CONFIG
REGION = "eu"
LOCALE = "en_GB"
API_HOST = f"{REGION}.api.blizzard.com"
API_BASE = f"https://{API_HOST}"
NAMESPACE_STATIC = f"static-{REGION}"
NAMESPACE_PROFILE = f"profile-{REGION}"
OUTFILE = Path(f"achiev/region_{REGION}.x")

# Known PvP category IDs
PVP_CATEGORY_IDS = [95, 165, 167, 168, 169]

# Current season and brackets to include
PVP_SEASON_ID = 38
BRACKETS = ["2v2", "3v3", "rbg", "shuffle"]

# Inline token auth
def get_access_token(region):
    client_id = os.environ["BLIZZARD_CLIENT_ID"]
    client_secret = os.environ["BLIZZARD_CLIENT_SECRET"]
    url = f"https://{region}.battle.net/oauth/token"
    response = requests.post(
        url,
        data={"grant_type": "client_credentials"},
        auth=(client_id, client_secret)
    )
    response.raise_for_status()
    return response.json()["access_token"]

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
        semaphore = asyncio.Semaphore(10)  # Adjust concurrency as needed

        async def process_one(char):
            async with semaphore:
                name = char["name"]
                realm = char["realm"]
                guid = char["id"]
                char_key = f"{name.lower()}-{realm.lower()}"

                data = await get_character_achievements(session, headers, realm, name)
                if not data:
                    return None

                earned = data.get("achievements", [])
                earned_pvp = [
                    (ach["id"], pvp_achievements[ach["id"]])
                    for ach in earned
                    if ach["id"] in pvp_achievements
                ]

                if not earned_pvp:
                    return None

                entry = {
                    "character": char_key,
                    "guid": guid
                }
                for idx, (aid, aname) in enumerate(earned_pvp, 1):
                    entry[f"id{idx}"] = aid
                    entry[f"name{idx}"] = aname

                return json.dumps(entry, separators=(",", ":"))

        tasks = [process_one(char) for char in characters_by_guid.values()]
        results = await asyncio.gather(*tasks)

        with open(OUTFILE, "w") as f:
            for line in results:
                if line:
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
