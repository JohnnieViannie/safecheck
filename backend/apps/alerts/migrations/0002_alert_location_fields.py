from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("alerts", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="alert",
            name="location_accuracy_m",
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="alert",
            name="location_label",
            field=models.CharField(blank=True, max_length=500),
        ),
        migrations.AddField(
            model_name="alert",
            name="location_source",
            field=models.CharField(
                blank=True,
                choices=[
                    ("gps", "GPS"),
                    ("opencellid", "OpenCellID"),
                    ("sms", "SMS"),
                ],
                default="sms",
                max_length=20,
            ),
        ),
    ]
