from django.contrib import admin

from apps.checkins.models import CallAttempt, Checkin

admin.site.register(Checkin)
admin.site.register(CallAttempt)
