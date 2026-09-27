"""
storage_location.py
Where the images live (students' drawings, exercise photos): the bucket
named by IMAGES_BUCKET (in production, mathclass-a9328-zurich in Zurich,
europe-west6), else the project's default bucket (emulators, tests).
"""

import os


def images_bucket(storage_module):
    """The images bucket, through the caller's firebase_admin.storage."""
    name = os.environ.get("IMAGES_BUCKET", "").strip()
    return storage_module.bucket(name) if name else storage_module.bucket()
