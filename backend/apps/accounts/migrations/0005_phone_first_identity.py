import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models

from apps.accounts.phone import PLACEHOLDER_EMAIL_DOMAIN, find_phone_issues, normalize_phone


def check_phones(apps, schema_editor):
    """Stop before any schema change: MySQL can't roll back DDL if this fails later."""
    User = apps.get_model("accounts", "User")
    issues = find_phone_issues(User.objects.values_list("id", "phone", "country_code"))
    if issues:
        raise RuntimeError(
            "Fix these phone numbers before migrating "
            "(see `manage.py audit_phone_numbers`):\n" + "\n".join(issues)
        )


def normalize_identity(apps, schema_editor):
    User = apps.get_model("accounts", "User")
    User.objects.filter(phone="").update(phone=None)
    User.objects.filter(email="").update(email=None)
    User.objects.filter(email__iendswith=PLACEHOLDER_EMAIL_DOMAIN).update(
        email=None, email_verified=False
    )
    for user in User.objects.exclude(phone=None):
        normalized = normalize_phone(user.phone, user.country_code)
        if normalized != user.phone:
            user.phone = normalized
            user.save(update_fields=["phone"])


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0004_user_is_muted"),
    ]

    operations = [
        migrations.RunPython(check_phones, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="user",
            name="email",
            field=models.EmailField(blank=True, db_index=True, max_length=254, null=True, unique=True),
        ),
        migrations.AlterField(
            model_name="user",
            name="phone",
            field=models.CharField(blank=True, max_length=32, null=True, help_text="E.164 format"),
        ),
        migrations.AddField(
            model_name="user",
            name="phone_verified",
            field=models.BooleanField(default=False),
        ),
        migrations.RunPython(normalize_identity, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="user",
            name="phone",
            field=models.CharField(
                blank=True, help_text="E.164 format", max_length=32, null=True, unique=True
            ),
        ),
        migrations.AddField(
            model_name="emailverificationtoken",
            name="attempts",
            field=models.PositiveSmallIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="passwordresettoken",
            name="attempts",
            field=models.PositiveSmallIntegerField(default=0),
        ),
        migrations.CreateModel(
            name="PhoneVerificationToken",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("token", models.CharField(db_index=True, max_length=64)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("expires_at", models.DateTimeField()),
                ("used_at", models.DateTimeField(blank=True, null=True)),
                ("attempts", models.PositiveSmallIntegerField(default=0)),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="phone_tokens",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
        ),
    ]
