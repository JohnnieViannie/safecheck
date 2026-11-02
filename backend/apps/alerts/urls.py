from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    AlertCodeViewSet,
    AlertViewSet,
    africastalking_sms_webhook,
    bracelet_sos_cell,
    bracelet_sos_gps,
)

router = DefaultRouter()
router.register("alerts", AlertViewSet, basename="alerts")
router.register("alert-codes", AlertCodeViewSet, basename="alert-codes")

urlpatterns = [
    path("webhooks/africastalking/sms/", africastalking_sms_webhook),
    path("bracelets/sos/gps/", bracelet_sos_gps),
    path("bracelets/sos/cell/", bracelet_sos_cell),
    path("", include(router.urls)),
]
