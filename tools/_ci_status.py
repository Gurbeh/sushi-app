import json, subprocess, sys
run = sys.argv[1]
raw = subprocess.check_output(
    ["gh", "run", "view", run, "--repo", "Gurbeh/sushi-app", "--json", "status,conclusion,jobs"],
    text=True,
)
d = json.loads(raw)
print("run", d["status"], d.get("conclusion"))
for j in d.get("jobs") or []:
    print(f"{j['name']}: {j['status']} {j.get('conclusion')}")
