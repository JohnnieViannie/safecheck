"""Generated login names: a person's first name plus digits, e.g. amina4821."""
import re
import secrets
import unicodedata


def _name_part(*names) -> str:
    for name in names:
        ascii_name = unicodedata.normalize("NFKD", name or "").encode("ascii", "ignore").decode()
        letters = re.sub(r"[^a-z]", "", ascii_name.lower())
        if letters:
            return letters[:20]
    return "user"


def generate_username(user_model, first_name="", last_name="") -> str:
    base = _name_part(first_name, last_name)
    for digits in (4, 4, 4, 4, 4, 6, 6, 6, 8):
        candidate = f"{base}{secrets.randbelow(9 * 10 ** (digits - 1)) + 10 ** (digits - 1)}"
        if not user_model.objects.filter(username=candidate).exists():
            return candidate
    raise RuntimeError("Could not generate a unique username.")
