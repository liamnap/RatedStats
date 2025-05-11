import os
import json
import asyncio
import aiohttp
import requests
from pathlib import Path

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

PVP_CATEGORY_IDS = [95, 165, 167, 168, 169]
PVP_SEASON_ID = 38
BRACKETS = ["2v2", "3v3", "rbg", "shuffle"]

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

# FETCH WRAPPER
async def fetch(session, url, headers):
    async with session.get(url, headers=headers) as r:
        if r.status != 200:
            print(f"[FAIL] {url} - {r.status}")
            return {}
        return await r.json()

# PVP ACHIEVEMENTS
async def get_pvp_achievements(session, headers):
    out = {}
    for cid in PVP_CATEGORY_IDS:
        url = f"{API_BASE}/data/wow/achievement-category/{cid}?namespace={NAMESPACE_STATIC}&locale={LOCALE}"
        data = await fetch(session, url, headers)
        for ach in data.get("achievements", []):
            out[ach["id"]] = ach["name"]
    return out

# CHAR ACHIEVEMENTS
async def get_character_achievements(session, headers, realm, name):
    url = f"{API_BASE}/profile/wow/character/{realm}/{name.lower()}/achievements?namespace={NAMESPACE_PROFILE}&locale={LOCALE}"
    return await fetch(session, url, headers)

# MAIN
async def process_characters(characters):
    token = get_access_token(REGION)
    headers = {"Authorization": f"Bearer {token}"}

    async with aiohttp.ClientSession() as session:
        pvp_achievements = await get_pvp_achievements(session, headers)
        semaphore = asyncio.Semaphore(10)

        async def process_one(char):
            async with semaphore:
                name, realm, guid = char["name"].lower(), char["realm"].lower(), char["id"]
                char_key = f"{name}-{realm}"
                data = await get_character_achievements(session, headers, realm, name)
                if not data:
                    return None
                earned = data.get("achievements", [])
                matches = [(a["id"], pvp_achievements[a["id"]]) for a in earned if a["id"] in pvp_achievements]
                if not matches:
                    return None
                entry = {"character": char_key, "guid": guid}
                for i, (aid, aname) in enumerate(matches, 1):
                    entry[f"id{i}"] = aid
                    entry[f"name{i}"] = aname
                print(f"[OK] {char_key} - {len(matches)}")
                return json.dumps(entry, separators=(",", ":"))

        tasks = [process_one(c) for c in characters.values()]
        results = await asyncio.gather(*tasks)
        lines = [r for r in results if r]
        lines.sort(key=lambda l: json.loads(l)["character"])

        with open(OUTFILE, "w", encoding="utf-8") as f:
            f.write(f'-- File: RatedStats/achiev/region_{REGION}.lua\n')
            f.write("local achievements = {\n")
            for line in lines:
                obj = json.loads(line)
                parts = [f'character = "{obj["character"]}", guid = {obj["guid"]}']
                for i in range(1, 100):
                    id_key = f"id{i}"
                    name_key = f"name{i}"
                    if id_key in obj and name_key in obj:
                        name = obj[name_key].replace('"', '\\"')
                        parts.append(f'id{i} = {obj[id_key]}, name{i} = "{name}"')
                    else:
                        break
                lua_line = "    { " + ", ".join(parts) + " },\n"
                f.write(lua_line)
            f.write("}\n\n")
            f.write(f"{REGION_VAR} = achievements\n")

# RUN
if __name__ == "__main__":
    token = get_access_token(REGION)
    headers = {"Authorization": f"Bearer {token}"}
    chars = get_characters_from_leaderboards(REGION, headers, PVP_SEASON_ID, BRACKETS)
    asyncio.run(process_characters(chars))
