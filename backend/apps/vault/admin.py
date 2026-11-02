from django.contrib import admin

from apps.vault.models import VaultDocument, VaultReleaseToken

admin.site.register(VaultDocument)
admin.site.register(VaultReleaseToken)
