from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin

from .models import User


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    ordering = ("email",)
    list_display = ("username", "phone", "email", "first_name", "last_name", "is_platform_admin", "is_active")
    search_fields = ("username", "phone", "email", "first_name", "last_name")
    fieldsets = (
        (None, {"fields": ("username", "phone", "email", "password")}),
        ("Profile", {"fields": ("first_name", "last_name", "account_type", "city", "address", "photo", "platform_role")}),
        (
            "Permissions",
            {
                "fields": (
                    "is_active",
                    "is_staff",
                    "is_superuser",
                    "is_platform_admin",
                    "phone_verified",
                    "email_verified",
                    "groups",
                    "user_permissions",
                )
            },
        ),
    )
    add_fieldsets = (
        (
            None,
            {
                "classes": ("wide",),
                "fields": ("phone", "email", "password1", "password2", "is_platform_admin"),
            },
        ),
    )
    filter_horizontal = ("groups", "user_permissions")
