import httpx
import certifi

url = "https://opendata.samtrafiken.se/gtfs/sweden3/latest.zip"
print('Using certifi CA bundle:', certifi.where())
try:
    with httpx.stream('GET', url, timeout=30.0, verify=certifi.where()) as r:
        r.raise_for_status()
        print('Success: status', r.status_code)
except Exception as e:
    print('Error:', repr(e))
