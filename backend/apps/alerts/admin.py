from django.contrib import admin

from .models import Alert, AlertCode, InboundSmsEvent

admin.site.register(Alert)
admin.site.register(AlertCode)
admin.site.register(InboundSmsEvent)
