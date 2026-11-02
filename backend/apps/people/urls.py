from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import PersonViewSet, TrustedContactViewSet

router = DefaultRouter()
router.register("people", PersonViewSet, basename="people")
router.register("trusted-contacts", TrustedContactViewSet, basename="trusted-contacts")

urlpatterns = [path("", include(router.urls))]
