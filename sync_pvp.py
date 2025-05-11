import os
import requests
import datetime

BASE_VERSION = "v2.0"
CLIENT_ID = os.getenv("BLIZZARD_CLIENT_ID")
CLIENT_SECRET = os.getenv("BLIZZARD_CLIENT_SECRET")

PLAYERS_BY_REGION = {
    "eu": [("liami", "emeriss")],
    "us": [],
    "kr": [],
    "tw": []
}

def is_pvp_achievement(achievement):
    # Known PvP-related category IDs
    category_id = achievement.get("category", {}).get("id")
    return category_id in [95, 165, 15092, 15266, 15270, 15279]

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
    if r.status_code == 200:
        return r.json()
    return {}

def is_pvp_category(cat_id):
    # Expand as needed from official PvP categories
    return cat_id in [95, 165, 15092, 15266, 15270, 15279]

def get_achievement_info(aid, region, token):
    url = f"https://{region}.api.blizzard.com/data/wow/achievement/{aid}"
    params = {
        "namespace": f"static-{region}",
        "locale": "en_GB",
        "access_token": token
    }
    r = requests.get(url, params=params)
    if r.status_code == 200:
        return r.json()
    return {}

def extract_pvp_achievements(data, region, token):
    pvp = []
    for a in data.get("achievements", []):
        aid = a.get("id")
        if not aid:
            continue
        details = get_achievement_info(aid, region, token)
        cat = details.get("category", {}).get("id")
        if cat and is_pvp_category(cat):
            name = details.get("name", "Unknown")
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

        # Prefer formatted name from API if available
        char_name = data.get("character", {}).get("name", name).capitalize()
        char_realm = data.get("character", {}).get("realm", {}).get("slug", realm).replace("-", " ").title().replace(" ", "-")
        key = f"{char_name}-{char_realm}"

        print(f"✅ {key} → {len(summary)} achievements")
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
            achievement_str = ",".join(achievements)
            f.write(f'  ["{char_key}"] = "{achievement_str}",\n')
        f.write("}\n")

def main():
    for region, players in PLAYERS_BY_REGION.items():
        if players:
            save_region(region, players)

if __name__ == "__main__":
    main()
