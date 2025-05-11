import os
import json
import asyncio
import aiohttp
import requests
from pathlib import Path

# REGION/LOCALE MATCH ORIGINAL
REGION = "eu"
LOCALE = "en_GB"
API_HOST = f"{REGION}.api.blizzard.com"
API_BASE = f"https://{API_HOST}"
NAMESPACE_STATIC = f"static-{REGION}"
NAMESPACE_PROFILE = f"profile-{REGION}"
OUTFILE = Path(f"achiev/region_{REGION}.x")

# Known PvP category IDs
PVP_CATEGORY_IDS = [95, 165, 167, 168, 169]

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

# Fetch helper
async def fetch(session, url, headers):
    async with session.get(url, headers=headers) as resp:
        if resp.status != 200:
            print(f"Failed: {url} - {resp.status}")
            return {}
        return await resp.json()

# PvP achievements by category
async def get_pvp_achievements(session, headers):
    achievements = {}
    for category_id in PVP_CATEGORY_IDS:
        url = f"{API_BASE}/data/wow/achievement-category/{category_id}?namespace={NAMESPACE_STATIC}&locale={LOCALE}"
        data = await fetch(session, url, headers)
        for ach in data.get("achievements", []):
            achievements[ach["id"]] = ach["name"]
    return achievements

# Character achievement fetch
async def get_character_achievements(session, headers, realm, name):
    url = f"{API_BASE}/profile/wow/character/{realm}/{name.lower()}/achievements?namespace={NAMESPACE_PROFILE}&locale={LOCALE}"
    return await fetch(session, url, headers)

# Main process logic
async def process_characters(characters):
    token = get_access_token(REGION)
    headers = { "Authorization": f"Bearer {token}" }

    async with aiohttp.ClientSession() as session:
        pvp_achievements = await get_pvp_achievements(session, headers)

        with open(OUTFILE, "w") as f:
            for realm, char_names in characters.items():
                for name in char_names:
                    data = await get_character_achievements(session, headers, realm, name)
                    if not data:
                        continue

                    char_guid = data.get("character", {}).get("id", None)
                    char_key = f"{name.lower()}-{realm.lower()}"

                    earned = data.get("achievements", [])
                    earned_pvp = [
                        (ach["id"], pvp_achievements[ach["id"]])
                        for ach in earned
                        if ach["id"] in pvp_achievements
                    ]

                    if not earned_pvp:
                        continue

                    entry = {
                        "character": char_key,
                        "guid": char_guid
                    }

                    for idx, (aid, aname) in enumerate(earned_pvp, 1):
                        entry[f"id{idx}"] = aid
                        entry[f"name{idx}"] = aname

                    f.write(json.dumps(entry, separators=(",", ":")) + "\n")
                    print(f"Stored: {char_key} with {len(earned_pvp)} PvP achievements")

# Example characters
if __name__ == "__main__":
    characters = {
        "emeriss": ["Liami"],
        "stormscale": ["Anotherchar"]
    }

    asyncio.run(process_characters(characters))
