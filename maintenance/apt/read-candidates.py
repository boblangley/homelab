import json
import platform
import sys

import apt

os_release = platform.freedesktop_os_release()
updates = []
for package in apt.Cache():
    if not package.is_upgradable:
        continue
    installed = package.installed
    candidate = package.candidate
    origins = sorted({(origin.origin, origin.archive) for origin in candidate.origins})
    updates.append({
        "package": package.shortname,
        "architecture": candidate.architecture,
        "installed_version": installed.version,
        "candidate_version": candidate.version,
        "source_package": candidate.source_name,
        "source_version": candidate.source_version,
        "origins": [{"origin": origin, "archive": archive} for origin, archive in origins],
    })

print(json.dumps({
    "host": sys.argv[1],
    "os": {
        "id": os_release["ID"],
        "version": os_release["VERSION_ID"],
        "codename": os_release.get("VERSION_CODENAME"),
    },
    "updates": sorted(updates, key=lambda row: (row["package"], row["architecture"])),
}))
