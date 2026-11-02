from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import BraceletViewSet

router = DefaultRouter()
router.register("bracelets", BraceletViewSet, basename="bracelets")

urlpatterns = [path("", include(router.urls))]
