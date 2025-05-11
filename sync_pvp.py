import os
import requests
from datetime import datetime, UTC

BASE_VERSION = "v2.0"
CLIENT_ID = os.getenv("BLIZZARD_CLIENT_ID")
CLIENT_SECRET = os.getenv("BLIZZARD_CLIENT_SECRET")

PLAYERS_BY_REGION = {
    "eu": [("liami", "emeriss")],
    "us": [],
    "kr": [],
    "tw": []
}

PVP_CATEGORIES = {95, 165, 15092, 15266, 15270, 15279}

def get_token(region):
    print(f"🔐 Requesting token for region: {region}", flush=True)
    url = f"https://{region}.battle.net/oauth/token"
    try:
        r = requests.post(
            url,
            data={"grant_type": "client_credentials"},
            auth=(CLIENT_ID, CLIENT_SECRET),
            timeout=10
        )
        r.raise_for_status()
        token = r.json()["access_token"]
        print(f"✅ Token received for {region}", flush=True)
        return token
    except requests.RequestException as e:
        print(f"❌ Failed to retrieve token for {region}: {e}", flush=True)
        return None

def verify_character_exists(name, realm, region, token):
    url = f"https://{region}.api.blizzard.com/profile/wow/character/{realm}/{name}"
    params = {"namespace": f"profile-{region}", "locale": "en_GB"}
    headers = { "Authorization": f"Bearer {token}" }
    r = requests.get(url, headers=headers, params=params, timeout=10)
    if r.status_code != 200:
        print(f"❌ Character not found: {name}-{realm} ({region}) → {r.status_code}")
        return False
    return True

def get_achievements(name, realm, region, token):
    url = f"https://{region}.api.blizzard.com/profile/wow/character/{realm}/{name}/achievements"
    params = {"namespace": f"profile-{region}", "locale": "en_GB"}
    headers = { "Authorization": f"Bearer {token}" }
    r = requests.get(url, headers=headers, params=params, timeout=10)
    if r.status_code == 200:
        return r.json()
    print(f"❌ Failed to fetch achievements for {name}-{realm}: {r.status_code}")
    print(f"URL: {r.url}")
    return {}

def get_achievement_info(aid, region, token):
    url = f"https://{region}.api.blizzard.com/data/wow/achievement/{aid}"
    params = {
        "namespace": f"static-{region}",
        "locale": "en_GB"
    }
    headers = { "Authorization": f"Bearer {token}" }
    r = requests.get(url, headers=headers, params=params, timeout=10)
    if r.status_code == 200:
        return r.json()
    return {}
    
import time
start = time.time()

def extract_pvp_achievements(data, region, token):
    print(f"⏱️ Took {time.time() - start:.2f} seconds to extract PvP achievements")
    pvp = []
    for a in data.get("achievements", []):
        aid = a.get("id")
        if not aid:
            continue
        details = get_achievement_info(aid, region, token)
        cat = details.get("category", {}).get("id")
        if cat in PVP_CATEGORIES:
            name = details.get("name", "Unknown")
            pvp.append(f"{aid}:{name}")
    return pvp

def save_region(region, players):
    token = get_token(region)
    if not token:
        print(f"❌ Skipping region {region} due to token failure", flush=True)
        return
    all_data = {}

    for name, realm in players:
        name = name.lower()
        realm = realm.lower()

        if not verify_character_exists(name, realm, region, token):
            print("⚠️ Skipping character due to failed verification.")
            if not (name == "liami" and realm == "emeriss"):
                continue

        # Diagnostic
        if name == "liami" and realm == "emeriss":
            print("🛠 Running diagnostic check for Liami-Emeriss")
            debug_url = f"https://{region}.api.blizzard.com/profile/wow/character/emeriss/liami/achievements"
            debug_params = {"namespace": f"profile-{region}", "locale": "en_GB"}
            debug_headers = { "Authorization": f"Bearer {token}" }
            r = requests.get(debug_url, headers=debug_headers, params=debug_params, timeout=10)
            print(f"🧪 Diagnostic status: {r.status_code}")
            print(f"🧪 Full URL: {r.url}")
            print(f"🧪 Response: {r.text[:300]}...")

        data = get_achievements(name, realm, region, token)
        if not data.get("achievements"):
            print(f"⚠️  No achievements found for {name}-{realm}")
            continue

        summary = extract_pvp_achievements(data, region, token)
        if not summary:
            print(f"ℹ️  No PvP achievements found for {name}-{realm}")
            continue

        char_name = data.get("character", {}).get("name", name).capitalize()
        char_realm = data.get("character", {}).get("realm", {}).get("slug", realm).replace("-", " ").title().replace(" ", "-")
        key = f"{char_name}-{char_realm}"

        print(f"✅ {key} → {len(summary)} PvP achievements")
        all_data[key] = summary

    today = datetime.now(UTC)
    version = f"{BASE_VERSION}-day{today.timetuple().tm_yday}-{today.year}"
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
