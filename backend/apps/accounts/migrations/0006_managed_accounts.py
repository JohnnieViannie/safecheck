import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models

from apps.accounts.usernames import generate_username


def fill_usernames(apps, schema_editor):
    User = apps.get_model("accounts", "User")
    for user in User.objects.filter(username__isnull=True):
        user.username = generate_username(User, user.first_name, user.last_name)
        user.save(update_fields=["username"])


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0005_phone_first_identity"),
    ]

    operations = [
        migrations.AddField(
            model_name="user",
            name="username",
            field=models.CharField(blank=True, max_length=64, null=True),
        ),
        migrations.RunPython(fill_usernames, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="user",
            name="username",
            field=models.CharField(blank=True, max_length=64, unique=True),
        ),
        migrations.AddField(
            model_name="user",
            name="city",
            field=models.CharField(blank=True, max_length=100),
        ),
        migrations.AddField(
            model_name="user",
            name="address",
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name="user",
            name="photo",
            field=models.ImageField(blank=True, null=True, upload_to="profile_photos/%Y/%m/"),
        ),
        migrations.AddField(
            model_name="user",
            name="platform_role",
            field=models.CharField(
                blank=True, choices=[("registrar", "Registrar")], default="", max_length=20
            ),
        ),
        migrations.AddField(
            model_name="user",
            name="registered_by",
            field=models.ForeignKey(
                blank=True,
                help_text="Staff member who registered this person.",
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="registered_users",
                to=settings.AUTH_USER_MODEL,
            ),
        ),
    ]
