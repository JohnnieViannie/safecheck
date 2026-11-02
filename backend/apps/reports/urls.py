from django.urls import path

from .views import dashboard_summary, reports_summary

urlpatterns = [
    path("dashboard/summary/", dashboard_summary),
    path("reports/summary/", reports_summary),
]
