from django.contrib import admin

from apps.safety.models import (
    EscalationAlert,
    LocationSnapshot,
    SafetyProfile,
    SmsMessage,
    UserTimelineEvent,
)

admin.site.register(SafetyProfile)
admin.site.register(LocationSnapshot)
admin.site.register(EscalationAlert)
admin.site.register(UserTimelineEvent)
admin.site.register(SmsMessage)
