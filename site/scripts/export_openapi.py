"""Write the API's OpenAPI spec to frontend/openapi.json (input for `npm run gen-types`).

Usage: python scripts/export_openapi.py
"""

import json
from pathlib import Path

from altarmy_site import auth
from altarmy_site.api import create_app

OUT = Path(__file__).resolve().parents[1] / "frontend" / "openapi.json"

# Any project will do: the spec doesn't depend on it, and nothing is verified.
firebase = auth.FirebaseConfig("demo-altarmy", "", "demo-altarmy.firebaseapp.com", None)
spec = create_app(static_dir=None, firebase=firebase).openapi()
OUT.write_text(json.dumps(spec, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"wrote {OUT}")
