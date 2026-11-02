from django.contrib import admin

from .models import Person, TrustedContact

admin.site.register(Person)
admin.site.register(TrustedContact)
