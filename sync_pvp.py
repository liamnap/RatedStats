import os
import requests
import datetime
import json

BASE_VERSION = "v2.0"
CLIENT_ID = os.getenv("BLIZZARD_CLIENT_ID")
CLIENT_SECRET = os.getenv("BLIZZARD_CLIENT_SECRET")

PLAYERS_BY_REGION = {
    "eu": [("liami", "emeriss")],
    "us": [],
    "kr": [],
    "tw": []
}

# Load achievement metadata from static dump
with open("achievements_index.json", encoding="utf-8") as f:
    ALL_ACHIEVEMENTS = {str(a["id"]): a for a in json.load(f)["achievements"] if "id" in a}

# PvP-related category IDs
PVP_CATEGORY_IDS = {95, 165, 15092, 15266, 15270, 15279}

def is_pvp_category(cat_id):
    return cat_id in PVP_CATEGORY_IDS

def get_token(region):
    url = f"https://{region}.battle.net/oauth/token"
    r = requests.post(url, data={"grant_type": "client_credentials"}, auth=(CLIENT_ID, CLIENT_SECRET))
    r.raise_for_status()
    return r.json()["access_token"]

def get_achievements(name, realm, region, token):
    url = f"https://{region}.api.blizzard.com/profile/wow/character/{realm}/{name}/achievements"
    params = {
        "namespace": f"profile-{region}",
        "locale": "en_GB",
        "access_token": token
    }
    r = requests.get(url, params=params)
    if r.status_code != 200:
        print(f"❌ Failed or empty response for {name}-{realm} ({region})")
        print(f"Status: {r.status_code}, URL: {r.url}")
        return {}
    return r.json()

def extract_pvp_achievements(data):
    pvp = []
    for a in data.get("achievements", []):
        aid = str(a.get("id"))
        info = ALL_ACHIEVEMENTS.get(aid)
        if not info:
            continue
        cat = info.get("category", {}).get("id")
        if is_pvp_category(cat):
            name = info.get("name", "Unknown").replace('"', "'")
            pvp.append(f"{aid}:{name}")
    return pvp

def save_region(region, players):
    token = get_token(region)
    all_data = {}

    for name, realm in players:
        data = get_achievements(name.lower(), realm.lower(), region, token)
        if not data or not data.get("achievements"):
            print(f"⚠️  No data for {name}-{realm} in {region.upper()}")
            continue

        summary = extract_pvp_achievements(data)
        if not summary:
            print(f"ℹ️  No PvP achievements found for {name}-{realm}")
            continue

        char_name = data.get("character", {}).get("name", name).capitalize()
        char_realm = data.get("character", {}).get("realm", {}).get("slug", realm).replace("-", " ").title().replace(" ", "-")
        key = f"{char_name}-{char_realm}"

        print(f"✅ {key} → {len(summary)} PvP achievements")
        all_data[key] = summary

    today = datetime.datetime.utcnow()
    day = today.timetuple().tm_yday
    year = today.year
    version = f"{BASE_VERSION}-day{day}-{year}"
    filename = f"achiev/region_{region}.x"

    with open(filename, "w", encoding="utf-8") as f:
        f.write(f'PvPSeenVersion = "{version}"\n\n')
        f.write(f'PvPSeen_{region.upper()} = {{\n')
        for char_key, achievements in all_data.items():
            line = ",".join(achievements)
            f.write(f'  ["{char_key}"] = "{line}",\n')
        f.write("}\n")

def main():
    for region, players in PLAYERS_BY_REGION.items():
        if players:
            save_region(region, players)

if __name__ == "__main__":
    main()
