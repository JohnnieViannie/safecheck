"""Django settings for SafeBangle platform."""
from datetime import timedelta
from pathlib import Path
import os
import sys

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env", override=True)

# Test runs must never reach live SMS or voice providers, whatever .env holds.
if "test" in sys.argv:
    os.environ["SMS_PROVIDER"] = "africastalking"
    os.environ["VOICE_SMS_PROVIDER"] = "africastalking"
    for _key in ("AT_API_KEY", "AT_USERNAME", "KACYBER_APP_ID", "KACYBER_API_KEY"):
        os.environ[_key] = ""

SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "dev-insecure-change-me")
DEBUG = os.getenv("DJANGO_DEBUG", "1").strip().lower() in ("1", "true", "yes", "on")

_DEFAULT_ALLOWED_HOSTS = (
    "localhost,127.0.0.1,"
    "server.safebangle.com,safebangle.com,www.safebangle.com,api.safebangle.com"
)
ALLOWED_HOSTS = [
    h.strip()
    for h in os.getenv("DJANGO_ALLOWED_HOSTS", _DEFAULT_ALLOWED_HOSTS).split(",")
    if h.strip()
]

_DEFAULT_CSRF_ORIGINS = (
    "https://server.safebangle.com,"
    "https://safebangle.com,"
    "https://www.safebangle.com,"
    "http://localhost:3000,"
    "http://127.0.0.1:3000"
)
CSRF_TRUSTED_ORIGINS = [
    o.strip()
    for o in os.getenv("DJANGO_CSRF_TRUSTED_ORIGINS", _DEFAULT_CSRF_ORIGINS).split(",")
    if o.strip()
]

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "corsheaders",
    "django_filters",
    "rest_framework",
    "rest_framework_simplejwt",
    "apps.accounts",
    "apps.organizations",
    "apps.people",
    "apps.devices",
    "apps.alerts",
    "apps.incidents",
    "apps.notifications",
    "apps.reports",
    "apps.audit",
    # SafeCheck mobile domains (unified into Blaces).
    "apps.safety",
    "apps.checkins",
    "apps.journeys",
    "apps.vault",
    "apps.push",
    "apps.mobile_compat",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
if DATABASE_URL.startswith("postgresql://") or DATABASE_URL.startswith("postgres://"):
    # postgresql://user:pass@host:port/db
    import urllib.parse as up

    u = up.urlparse(DATABASE_URL)
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": u.path.lstrip("/"),
            "USER": u.username or "",
            "PASSWORD": u.password or "",
            "HOST": u.hostname or "",
            "PORT": str(u.port or 5432),
        }
    }
elif os.getenv("DB_NAME"):
    DATABASES = {
        "default": {
            "ENGINE": os.getenv("DB_ENGINE", "django.db.backends.postgresql"),
            "NAME": os.getenv("DB_NAME"),
            "USER": os.getenv("DB_USER", ""),
            "PASSWORD": os.getenv("DB_PASSWORD", ""),
            "HOST": os.getenv("DB_HOST", "localhost"),
            "PORT": os.getenv("DB_PORT", "5432"),
        }
    }
elif DEBUG:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }
else:
    raise RuntimeError("Database configuration required in production.")

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

AUTH_USER_MODEL = "accounts.User"
AUTHENTICATION_BACKENDS = ["apps.accounts.backends.PhoneOrEmailBackend"]

CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "safebangle-verification",
    }
}

# SafeCheck mobile compat / scheduler
SAFECHECK_ALLOW_MOCK_AUTH = os.getenv("SAFECHECK_ALLOW_MOCK_AUTH", "0").strip().lower() in (
    "1",
    "true",
    "yes",
    "on",
)
SAFECHECK_PUBLIC_BASE_URL = os.getenv(
    "SAFECHECK_PUBLIC_BASE_URL", "https://safebangle.com"
).rstrip("/")
CALLBACK_BASE_URL = os.getenv("CALLBACK_BASE_URL", "").rstrip("/")
SMS_PROVIDER = os.getenv("SMS_PROVIDER", "africastalking")
VOICE_SMS_PROVIDER = os.getenv("VOICE_SMS_PROVIDER", "africastalking")
FIREBASE_CREDENTIALS_PATH = os.getenv("FIREBASE_CREDENTIALS_PATH", "")
FIREBASE_CREDENTIALS_JSON = os.getenv("FIREBASE_CREDENTIALS_JSON", "")

# Alias AT_SMS_URL used by notifications; also support AT_SMS_BASE_URL from SafeCheck.
_at_sms_base = os.getenv("AT_SMS_BASE_URL", "").strip()
if _at_sms_base and not os.getenv("AT_SMS_URL"):
    os.environ["AT_SMS_URL"] = _at_sms_base


CORS_ALLOWED_ORIGINS = [
    o.strip()
    for o in os.getenv(
        "DJANGO_CORS_ORIGINS", "http://localhost:3000,http://127.0.0.1:3000"
    ).split(",")
    if o.strip()
]
CORS_ALLOW_CREDENTIALS = True

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_FILTER_BACKENDS": (
        "django_filters.rest_framework.DjangoFilterBackend",
        "rest_framework.filters.SearchFilter",
        "rest_framework.filters.OrderingFilter",
    ),
    "DEFAULT_PAGINATION_CLASS": "config.pagination.StandardPagination",
    "PAGE_SIZE": 25,
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "anon": "60/min",
        "user": "300/min",
        "auth": "20/min",
        "webhook": "120/min",
        "bracelet_sos": "60/min",
    },
    "EXCEPTION_HANDLER": "config.exceptions.custom_exception_handler",
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=60),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=7),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": False,
}

EMAIL_BACKEND = os.getenv(
    "EMAIL_BACKEND", "django.core.mail.backends.console.EmailBackend"
)
EMAIL_HOST = os.getenv("EMAIL_HOST", "")
EMAIL_PORT = int(os.getenv("EMAIL_PORT", "587") or 587)
EMAIL_USE_TLS = os.getenv("EMAIL_USE_TLS", "1").strip().lower() in ("1", "true", "yes")
EMAIL_USE_SSL = os.getenv("EMAIL_USE_SSL", "0").strip().lower() in ("1", "true", "yes")
EMAIL_HOST_USER = os.getenv("EMAIL_HOST_USER", "").strip()
EMAIL_HOST_PASSWORD = os.getenv("EMAIL_HOST_PASSWORD", "").strip()
EMAIL_TIMEOUT = int(os.getenv("EMAIL_TIMEOUT", "15") or 15)
DEFAULT_FROM_EMAIL = os.getenv(
    "DEFAULT_FROM_EMAIL", "SafeBangle <hello@safebangle.com>"
)

FRONTEND_URL = os.getenv("FRONTEND_URL", "http://localhost:3000").rstrip("/")

AT_USERNAME = os.getenv("AT_USERNAME", "")
AT_API_KEY = os.getenv("AT_API_KEY", "")
AT_SENDER_ID = os.getenv("AT_SENDER_ID", "")
AT_SMS_URL = os.getenv(
    "AT_SMS_URL", "https://api.africastalking.com/version1/messaging"
)
WEBHOOK_SHARED_SECRET = os.getenv("WEBHOOK_SHARED_SECRET", "")
BRACELET_API_SECRET = os.getenv("BRACELET_API_SECRET", "")

OPENCELLID_API_KEY = os.getenv("OPENCELLID_API_KEY", "")
OPENCELLID_BASE_URL = os.getenv("OPENCELLID_BASE_URL", "https://opencellid.org").rstrip(
    "/"
)
NOMINATIM_REVERSE_URL = os.getenv(
    "NOMINATIM_REVERSE_URL", "https://nominatim.openstreetmap.org/reverse"
)
NOMINATIM_USER_AGENT = os.getenv(
    "NOMINATIM_USER_AGENT", "SafeBangle/1.0 (alerts@safebangle.com)"
)
ALERT_DEFAULT_TIMEZONE = os.getenv("ALERT_DEFAULT_TIMEZONE", "Africa/Kampala")
GEO_HTTP_TIMEOUT = int(os.getenv("GEO_HTTP_TIMEOUT", "8") or 8)

BRACELET_SMS_REGEX = os.getenv(
    "BRACELET_SMS_REGEX",
    r"^SB\|(?P<device_id>[^|]+)\|(?P<alert_code>[^|]+)\|(?P<lat>-?\d+(?:\.\d+)?)\|(?P<lng>-?\d+(?:\.\d+)?)$",
)

INVITATION_EXPIRY_HOURS = int(os.getenv("INVITATION_EXPIRY_HOURS", "72"))
EMAIL_VERIFICATION_EXPIRY_HOURS = int(os.getenv("EMAIL_VERIFICATION_EXPIRY_HOURS", "24"))
EMAIL_CODE_EXPIRY_MINUTES = int(os.getenv("EMAIL_CODE_EXPIRY_MINUTES", "15"))
PASSWORD_RESET_CODE_EXPIRY_MINUTES = int(
    os.getenv("PASSWORD_RESET_CODE_EXPIRY_MINUTES", "15")
)

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "root": {"handlers": ["console"], "level": "INFO"},
    "loggers": {
        "apps": {"handlers": ["console"], "level": "INFO", "propagate": False},
    },
}
