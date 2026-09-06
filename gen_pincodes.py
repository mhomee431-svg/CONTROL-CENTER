import json, collections

rows = []
with open(r"C:\Users\akash\OneDrive\Documents\hyperlocal_customer_app\IN_extract\IN.txt", encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 5:
            continue
        # 0=country,1=postal,2=place,3=admin1(state),4=admin1code
        pincode = parts[1].strip()
        place = parts[2].strip()
        state = parts[3].strip()
        if pincode.isdigit() and len(pincode) == 6 and place and state:
            rows.append((pincode, place, state))

# For each pincode pick the most common place name (main city), tie by state.
by_pin = collections.defaultdict(collections.Counter)
for pin, place, state in rows:
    by_pin[pin][(place, state)] += 1

data = {}
for pin, counter in by_pin.items():
    (place, state), _ = counter.most_common(1)[0]
    data[pin] = {"c": place, "s": state}

out = r"C:\Users\akash\OneDrive\Documents\hyperlocal_customer_app\ShopkeeperApp\assets\pincodes.json"
import os
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    json.dump(data, f, separators=(",", ":"))

print("unique pincodes:", len(data))
print("file size KB:", round(os.path.getsize(out) / 1024))