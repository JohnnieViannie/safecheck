from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("organizations", "0001_initial"),
    ]

    operations = [
        migrations.AlterField(
            model_name="invitation",
            name="email",
            field=models.EmailField(blank=True, db_index=True, max_length=254),
        ),
        migrations.AddField(
            model_name="invitation",
            name="phone",
            field=models.CharField(blank=True, db_index=True, max_length=32),
        ),
    ]
