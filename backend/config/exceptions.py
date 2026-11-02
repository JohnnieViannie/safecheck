from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler

FIELD_LABELS = {
    "email": "Email",
    "password": "Password",
    "first_name": "First name",
    "last_name": "Last name",
    "phone": "Phone",
    "country_code": "Country",
    "sex": "Sex",
    "date_of_birth": "Date of birth",
    "account_type": "Account type",
    "organization_name": "Organization name",
    "code": "Code",
    "non_field_errors": "",
}


def _as_messages(value) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, (list, tuple)):
        out: list[str] = []
        for item in value:
            out.extend(_as_messages(item))
        return out
    if isinstance(value, dict):
        out = []
        for k, v in value.items():
            msgs = _as_messages(v)
            label = FIELD_LABELS.get(str(k), str(k).replace("_", " ").capitalize())
            for m in msgs:
                out.append(f"{label}: {m}" if label else m)
        return out
    return [str(value)]


def flatten_errors(data) -> str:
    messages = _as_messages(data)
    # de-dupe while preserving order
    seen = set()
    unique = []
    for m in messages:
        if m not in seen:
            seen.add(m)
            unique.append(m)
    return " · ".join(unique) if unique else "Request failed"


def custom_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if response is not None:
        data = response.data
        if isinstance(data, dict) and "detail" in data and len(data) == 1:
            response.data = {"error": str(data["detail"])}
        elif isinstance(data, list):
            response.data = {"error": flatten_errors(data)}
        elif isinstance(data, dict) and "error" not in data:
            message = flatten_errors(data)
            response.data = {"error": message, "details": data}
        return response
    return Response(
        {"error": "Internal server error"},
        status=status.HTTP_500_INTERNAL_SERVER_ERROR,
    )
