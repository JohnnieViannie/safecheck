from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('api', '0006_userprofile_emergency_contact_country_code'),
    ]

    operations = [
        migrations.AddField(
            model_name='userprofile',
            name='fcm_token',
            field=models.CharField(blank=True, max_length=512, null=True),
        ),
        migrations.AddField(
            model_name='userprofile',
            name='fcm_token_updated_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='userprofile',
            name='fcm_platform',
            field=models.CharField(blank=True, max_length=16, null=True),
        ),
        migrations.AddField(
            model_name='userprofile',
            name='snoozed_until',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='userprofile',
            name='last_push_sent_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='userprofile',
            name='pending_call_kit_id',
            field=models.CharField(blank=True, max_length=64, null=True),
        ),
    ]
