import os
import time
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

def fetch_achievement_index(region, token):
    url = f"https://{region}.api.blizzard.com/data/wow/achievement/index"
    params = {"namespace": f"static-{region}", "locale": "en_GB"}
    headers = { "Authorization": f"Bearer {token}" }
    r = requests.get(url, headers=headers, params=params, timeout=15)
    r.raise_for_status()
    return r.json().get("achievements", [])

def enrich_achievement_details(index, region, token):
    headers = { "Authorization": f"Bearer {token}" }
    achievement_data = {}
    print(f"📦 Enriching {len(index)} achievements...", flush=True)

    for i, entry in enumerate(index, 1):
        aid = entry.get("id")
        href = entry.get("key", {}).get("href")
        if not aid or not href:
            continue
        try:
            r = requests.get(href, headers=headers, timeout=5)
            if r.status_code == 200:
                info = r.json()
                achievement_data[aid] = {
                    "name": info.get("name"),
                    "category": info.get("category", {}).get("id")
                }
        except requests.RequestException:
            continue

        if i % 500 == 0:
            print(f"🔄 Loaded {i} achievement records...", flush=True)

    return achievement_data

def extract_pvp_achievements(data, achievement_data):
    total = len(data.get("achievements", []))
    print(f"📥 Extracting PvP achievements from {total} total...", flush=True)
    pvp = []

    for i, a in enumerate(data.get("achievements", []), 1):
        aid = a.get("id")
        info = achievement_data.get(aid)
        if not aid or not info:
            continue
        if info["category"] in PVP_CATEGORIES:
            pvp.append(f'{aid}:{info["name"]}')
        if i % 100 == 0:
            print(f"🔍 Checked {i} achievements...", flush=True)

    print(f"✅ Found {len(pvp)} PvP achievements", flush=True)
    return pvp

def save_region(region, players):
    token = get_token(region)
    if not token:
        print(f"❌ Skipping region {region} due to token failure", flush=True)
        return

    # Enrich PvP metadata once per region
    index = fetch_achievement_index(region, token)
    achievement_data = enrich_achievement_details(index, region, token)

    all_data = {}

    for name, realm in players:
        name = name.lower()
        realm = realm.lower()

        if not verify_character_exists(name, realm, region, token):
            print("⚠️ Skipping character due to failed verification.")
            if not (name == "liami" and realm == "emeriss"):
                continue

        if name == "liami" and realm == "emeriss":
            print("🛠 Running diagnostic check for Liami-Emeriss")
            debug_url = f"https://{region}.api.blizzard.com/profile
