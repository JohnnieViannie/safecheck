from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0003_user_sex_dob_country"),
    ]

    operations = [
        migrations.AddField(
            model_name="user",
            name="is_muted",
            field=models.BooleanField(
                default=False,
                help_text="When muted, suppress alert / SMS notifications for this user.",
            ),
        ),
    ]
