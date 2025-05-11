import os
import json
import asyncio
import aiohttp
from pathlib import Path
from util.auth import get_access_token

REGION = "us"
LOCALE = "en_US"
NAMESPACE_STATIC = f"static-{REGION}"
NAMESPACE_PROFILE = f"profile-{REGION}"
API_BASE = f"https://{REGION}.api.blizzard.com"
OUTFILE = Path(f"achiev/region_{REGION}.x")

PVP_CATEGORY_IDS = [95, 165, 167, 168, 169]

HEADERS = {
    "Authorization": f"Bearer {get_access_token(REGION)}"
}

async def fetch(session, url):
    async with session.get(url, headers=HEADERS) as resp:
        if resp.status != 200:
            print(f"Failed: {url} - {resp.status}")
            return {}
        return await resp.json()

async def get_pvp_achievements(session):
    achievements = {}
    for category_id in PVP_CATEGORY_IDS:
        url = f"{API_BASE}/data/wow/achievement-category/{category_id}?namespace={NAMESPACE_STATIC}&locale={LOCALE}"
        data = await fetch(session, url)
        for ach in data.get("achievements", []):
            achievements[ach["id"]] = ach["name"]
    return achievements  # {id: name}

async def get_character_achievements(session, realm, name):
    url = f"{API_BASE}/profile/wow/character/{realm}/{name.lower()}/achievements?namespace={NAMESPACE_PROFILE}&locale={LOCALE}"
    data = await fetch(session, url)
    return data

async def process_characters(characters):
    async with aiohttp.ClientSession() as session:
        pvp_achievements = await get_pvp_achievements(session)

        with open(OUTFILE, "w") as f:
            for realm, char_names in characters.items():
                for name in char_names:
                    data = await get_character_achievements(session, realm, name)
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

if __name__ == "__main__":
    # EXAMPLE characters dict (replace with real input)
    characters = {
        "emeriss": ["Liami"],
        "stormscale": ["Anotherchar"]
    }

    asyncio.run(process_characters(characters))
