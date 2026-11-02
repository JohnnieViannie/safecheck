from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import OrganizationViewSet, accept_invitation, revoke_invitation

router = DefaultRouter()
router.register("organizations", OrganizationViewSet, basename="organizations")

urlpatterns = [
    path("invitations/accept/", accept_invitation),
    path("invitations/<uuid:invitation_id>/revoke/", revoke_invitation),
    path("", include(router.urls)),
]
