from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    StaffViewSet,
    UserViewSet,
    change_password,
    detect_country,
    forgot_password,
    login,
    me,
    my_photo,
    register,
    resend_verification,
    reset_password,
    verify_code,
)

router = DefaultRouter()
router.register("users", UserViewSet, basename="users")
router.register("staff", StaffViewSet, basename="staff")

urlpatterns = [
    path("register/", register),
    path("login/", login),
    path("refresh/", TokenRefreshView.as_view()),
    path("me/", me),
    path("me/photo/", my_photo),
    path("geo/", detect_country),
    path("verify-phone/", verify_code),
    path("verify-email/", verify_code),
    path("resend-code/", resend_verification),
    path("resend-verification/", resend_verification),
    path("forgot-password/", forgot_password),
    path("reset-password/", reset_password),
    path("change-password/", change_password),
    path("", include(router.urls)),
]
