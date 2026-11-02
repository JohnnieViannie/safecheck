from django.contrib import admin

from .models import Invitation, Organization, OrganizationMembership

admin.site.register(Organization)
admin.site.register(OrganizationMembership)
admin.site.register(Invitation)
