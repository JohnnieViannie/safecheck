from django.conf import settings
from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path, re_path
from django.conf.urls.static import static

from apps.mobile_compat import views as mobile_views


def health(_request):
    return JsonResponse({"status": "ok", "service": "safebangle"})


urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/health/", health),
    # Mobile SafeCheck routes (FCM devices, checkins, vault, journeys, …).
    path("api/", include("apps.mobile_compat.urls")),
    # Escalation alerts by mobile uid (email or E.164 phone) — before Blaces AlertViewSet.
    re_path(
        r"^api/alerts/(?P<uid>[^/]+@[^/]+)/$",
        mobile_views.alerts,
        name="mobile_alerts_by_email",
    ),
    re_path(
        r"^api/alerts/(?P<uid>\+?\d{8,15})/$",
        mobile_views.alerts,
        name="mobile_alerts_by_phone",
    ),
    # Blaces auth (JWT) + org platform.
    path("api/auth/", include("apps.accounts.urls")),
    path("api/", include("apps.organizations.urls")),
    path("api/", include("apps.people.urls")),
    path("api/", include("apps.devices.urls")),
    path("api/", include("apps.alerts.urls")),
    path("api/", include("apps.incidents.urls")),
    path("api/", include("apps.notifications.urls")),
    path("api/", include("apps.reports.urls")),
    path("api/", include("apps.audit.urls")),
    path("api/", include("apps.safety.urls")),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
