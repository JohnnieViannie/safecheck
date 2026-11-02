from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("alerts", "0002_alert_location_fields"),
    ]

    operations = [
        migrations.AddField(
            model_name="alert",
            name="location_area",
            field=models.CharField(
                blank=True, help_text="Short place name used in text messages.", max_length=200
            ),
        ),
    ]
