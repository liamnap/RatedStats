import os
import requests
import datetime

BASE_VERSION = "v2.0"
CLIENT_ID = os.getenv("BLIZZARD_CLIENT_ID")
CLIENT_SECRET = os.getenv("BLIZZARD_CLIENT_SECRET")

PLAYERS_BY_REGION = {
    "eu": [("elitee", "twilights-hammer"), ("markwards", "ragnaros")],
    "us": [("bigarena", "tichondrius")],
    "kr": [],
    "tw": []
}

ACHIEVEMENT_MAPPING = {
    9232: "Glad",
    41019: "Elite",
    41018: "Duelist",
    41017: "RivalII",
    41016: "RivalI",
    # Add more IDs as needed
}

def get_token(region):
    url = f"https://{region}.battle.net/oauth/token"
    r = requests.post(url, data={"grant_type": "client_credentials"}, auth=(CLIENT_ID, CLIENT_SECRET))
    r.raise_for_status()
    return r.json()["access_token"]

def get_achievements(name, realm, region, token):
    url = f"https://{region}.api.blizzard.com/profile/wow/character/{realm}/{name}/achievements"
    params = {"namespace": f"profile-{region}", "locale": "en_GB", "access_token": token}
    r = requests.get(url, params=params)
    if r.status_code == 200:
        return r.json()
    return {}

def extract_counts(data):
    counts = {key: 0 for key in set(ACHIEVEMENT_MAPPING.values())}
    for a in data.get("achievements", []):
        id = a.get("id")
        cat = ACHIEVEMENT_MAPPING.get(id)
        if cat:
            counts[cat] += 1
    return counts

def save_region(region, players):
    token = get_token(region)
    all_data = {}
    for name, realm in players:
        data = get_achievements(name.lower(), realm.lower(), region, token)
        summary = extract_counts(data)
        encoded = " ".join([f"{k}:{v}" for k, v in summary.items() if v > 0])
        key = f"{name.capitalize()}-{realm.capitalize()}"
        all_data[key] = encoded

    today = datetime.datetime.utcnow()
    day = today.timetuple().tm_yday
    year = today.year
    version = f"{BASE_VERSION}-day{day}-{year}"
    filename = f"achiev/region_{region}.x"

    with open(filename, "w") as f:
        f.write(f'PvPSeenVersion = "{version}"\n\n')
        f.write(f'PvPSeen_{region.upper()} = {{\n')
        for key, line in all_data.items():
            f.write(f'  ["{key}"] = "{line}",\n')
        f.write("}\n")

def main():
    for region, players in PLAYERS_BY_REGION.items():
        if players:
            save_region(region, players)

if __name__ == "__main__":
    main()
