from pathlib import Path
import os
from urllib.parse import urlparse, unquote

BASE_DIR = Path(__file__).resolve().parent.parent


def _load_dotenv(dotenv_path: Path) -> None:
    if not dotenv_path.exists():
        return
    for raw_line in dotenv_path.read_text(encoding='utf-8').splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def _database_from_url(database_url: str):
    parsed = urlparse(database_url)
    scheme_to_engine = {
        'postgres': 'django.db.backends.postgresql',
        'postgresql': 'django.db.backends.postgresql',
        'pgsql': 'django.db.backends.postgresql',
        'mysql': 'django.db.backends.mysql',
    }
    engine = scheme_to_engine.get(parsed.scheme)
    if not engine:
        raise ValueError(
            f"Unsupported DATABASE_URL scheme '{parsed.scheme}'. "
            "Use postgres/postgresql or mysql."
        )
    return {
        'ENGINE': engine,
        'NAME': unquote(parsed.path.lstrip('/')),
        'USER': unquote(parsed.username or ''),
        'PASSWORD': unquote(parsed.password or ''),
        'HOST': parsed.hostname or '',
        'PORT': str(parsed.port or ''),
        'CONN_MAX_AGE': int(os.getenv('DB_CONN_MAX_AGE', '60')),
    }


def _split_csv_env(key: str, default: str = '') -> list[str]:
    raw = os.getenv(key, default).strip()
    if not raw:
        return []
    return [item.strip() for item in raw.split(',') if item.strip()]


# Production hostnames for SafeBangle only.
SAFEBANGLE_ALLOWED_HOSTS = (
    'safebangle.com',
    'www.safebangle.com',
    'api.safebangle.com',
)
SAFEBANGLE_TRUSTED_ORIGINS = (
    'https://safebangle.com',
    'https://www.safebangle.com',
    'https://api.safebangle.com',
)
LOCAL_DEV_HOSTS = ('localhost', '127.0.0.1')
LOCAL_DEV_ORIGINS = (
    'http://localhost:8000',
    'http://127.0.0.1:8000',
)


_load_dotenv(BASE_DIR / '.env')

SECRET_KEY = os.getenv('DJANGO_SECRET_KEY', 'django-ifgfg_4747g@g645468n7ud')
DEBUG = os.getenv('DJANGO_DEBUG', 'True').lower() in ('1', 'true', 'yes', 'on')
SAFECHECK_ALLOW_MOCK_AUTH = os.getenv('SAFECHECK_ALLOW_MOCK_AUTH', 'false').lower() in (
    '1', 'true', 'yes', 'on',
)

_configured_hosts = _split_csv_env('DJANGO_ALLOWED_HOSTS')
if _configured_hosts:
    ALLOWED_HOSTS = _configured_hosts
else:
    ALLOWED_HOSTS = list(SAFEBANGLE_ALLOWED_HOSTS)
    if DEBUG:
        ALLOWED_HOSTS.extend(LOCAL_DEV_HOSTS)

if '*' in ALLOWED_HOSTS:
    raise RuntimeError(
        'DJANGO_ALLOWED_HOSTS cannot include "*". Use safebangle.com hostnames only.'
    )

for host in ALLOWED_HOSTS:
    if host in LOCAL_DEV_HOSTS:
        if not DEBUG:
            raise RuntimeError(
                f'Local host "{host}" is not allowed when DJANGO_DEBUG=False.'
            )
        continue
    if not (host == 'safebangle.com' or host.endswith('.safebangle.com')):
        raise RuntimeError(
            f'Host "{host}" is not allowed. Only safebangle.com domains are permitted.'
        )

_configured_origins = _split_csv_env('DJANGO_CSRF_TRUSTED_ORIGINS')
if _configured_origins:
    CSRF_TRUSTED_ORIGINS = _configured_origins
else:
    CSRF_TRUSTED_ORIGINS = list(SAFEBANGLE_TRUSTED_ORIGINS)
    if DEBUG:
        CSRF_TRUSTED_ORIGINS.extend(LOCAL_DEV_ORIGINS)

CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
        'LOCATION': 'safecheck-verification',
    }
}

if not DEBUG:
    SECURE_SSL_REDIRECT = os.getenv('DJANGO_SECURE_SSL_REDIRECT', 'true').lower() in (
        '1', 'true', 'yes', 'on',
    )
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = int(os.getenv('DJANGO_HSTS_SECONDS', '31536000'))
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'api',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'server.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'server.wsgi.application'

DATABASE_URL = os.getenv('DATABASE_URL', '').strip()

if DATABASE_URL:
    DATABASES = {'default': _database_from_url(DATABASE_URL)}
else:
    db_engine = os.getenv('DB_ENGINE', '').strip()
    db_name = os.getenv('DB_NAME', '').strip()
    if not db_engine or not db_name:
        raise RuntimeError(
            'Database config missing. Set DATABASE_URL or DB_ENGINE + DB_NAME in server/.env.'
        )
    DATABASES = {
        'default': {
            'ENGINE': db_engine,
            'NAME': db_name,
            'USER': os.getenv('DB_USER', ''),
            'PASSWORD': os.getenv('DB_PASSWORD', ''),
            'HOST': os.getenv('DB_HOST', ''),
            'PORT': os.getenv('DB_PORT', ''),
            'CONN_MAX_AGE': int(os.getenv('DB_CONN_MAX_AGE', '60')),
        }
    }

AUTH_PASSWORD_VALIDATORS = []

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True
STATIC_URL = '/static/'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'
