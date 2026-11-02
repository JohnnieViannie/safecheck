"""Common country dial codes for phone registration."""

# (iso2, name, dial_code)
COUNTRY_DIAL_CODES = [
    ("KE", "Kenya", "+254"),
    ("UG", "Uganda", "+256"),
    ("TZ", "Tanzania", "+255"),
    ("RW", "Rwanda", "+250"),
    ("ET", "Ethiopia", "+251"),
    ("NG", "Nigeria", "+234"),
    ("GH", "Ghana", "+233"),
    ("ZA", "South Africa", "+27"),
    ("US", "United States", "+1"),
    ("GB", "United Kingdom", "+44"),
    ("CA", "Canada", "+1"),
    ("IN", "India", "+91"),
    ("AE", "United Arab Emirates", "+971"),
    ("DE", "Germany", "+49"),
    ("FR", "France", "+33"),
    ("NL", "Netherlands", "+31"),
    ("AU", "Australia", "+61"),
    ("BR", "Brazil", "+55"),
    ("CN", "China", "+86"),
    ("EG", "Egypt", "+20"),
    ("SS", "South Sudan", "+211"),
    ("SO", "Somalia", "+252"),
    ("CD", "DR Congo", "+243"),
    ("BI", "Burundi", "+257"),
    ("MW", "Malawi", "+265"),
    ("ZM", "Zambia", "+260"),
    ("ZW", "Zimbabwe", "+263"),
    ("SN", "Senegal", "+221"),
    ("CI", "Côte d'Ivoire", "+225"),
    ("CM", "Cameroon", "+237"),
]


def dial_codes_payload():
    return [
        {"iso2": iso, "name": name, "dial_code": dial}
        for iso, name, dial in COUNTRY_DIAL_CODES
    ]


def dial_for_iso(iso2: str) -> str | None:
    iso = (iso2 or "").upper()
    for code, _name, dial in COUNTRY_DIAL_CODES:
        if code == iso:
            return dial
    return None
